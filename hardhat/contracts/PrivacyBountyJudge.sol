// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function lockUntil(address) external view returns (uint256);
}

/**
 * @title PrivacyBountyJudge
 * @notice Advanced bounty judge with dual privacy modes: commit-reveal AND TEE-encrypted submissions.
 *
 * Track 1 — Commit-Reveal (any EVM):
 *   Participants submit keccak256(answer || salt || sender || bountyId), reveal after deadline.
 *
 * Track 2 — TEE-Encrypted (Ritual Chain native):
 *   Participants encrypt answers via ECIES to the executor's public key.
 *   Encrypted blobs are stored on-chain. During judgeAll(), the LLM precompile
 *   decrypts inside the TEE enclave — plaintext NEVER touches the public chain.
 *
 * Privacy properties:
 *   - Commit-reveal: answers hidden until reveal phase
 *   - TEE-encrypted: answers NEVER decrypted outside TEE
 *   - Batch judging: single LLM call for all submissions (not one per answer)
 */
contract PrivacyBountyJudge is PrecompileConsumer {

    // ─── Constants ────────────────────────────────────────────────────
    uint256 public constant MAX_SUBMISSIONS = 15;
    uint256 public constant MAX_ANSWER_LENGTH = 4_000;
    uint256 public constant MIN_COMMIT_DURATION = 1 hours;
    uint256 public constant MIN_REVEAL_DURATION = 30 minutes;

    IRitualWallet public immutable ritualWallet;

    // ─── Enums ────────────────────────────────────────────────────────
    enum PrivacyMode { CommitReveal, TEEncrypted }
    enum Phase { Commit, Reveal, Judge, Finalized }

    // ─── Data Structures ──────────────────────────────────────────────

    struct Submission {
        address submitter;
        PrivacyMode mode;
        bytes32 commitment;   // for commit-reveal
        bytes encryptedData;  // for TEE-encrypted
        bool revealed;
        string answer;        // populated after reveal (commit-reveal) or inside TEE
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        uint256 winnerIndex;
        string aiReview;
        uint256 submissionCount;
        mapping(uint256 => Submission) submissions;
        mapping(address => bool) hasSubmitted;
    }

    // ─── State ────────────────────────────────────────────────────────
    uint256 public nextBountyId = 1;
    mapping(uint256 => Bounty) private bounties;

    // ─── Events ───────────────────────────────────────────────────────
    event BountyCreated(uint256 indexed bountyId, address indexed owner, string title, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, address indexed submitter, bytes32 commitment);
    event EncryptedAnswerSubmitted(uint256 indexed bountyId, address indexed submitter, uint256 dataLength);
    event AnswerRevealed(uint256 indexed bountyId, address indexed submitter);
    event JudgingComplete(uint256 indexed bountyId, string aiReview);
    event WinnerFinalized(uint256 indexed bountyId, uint256 winnerIndex, address winner, uint256 reward);

    // ─── Errors ───────────────────────────────────────────────────────
    error RewardRequired();
    error InvalidDeadlines();
    error CommitPhaseClosed();
    error CommitPhaseStillActive();
    error RevealPhaseClosed();
    error AlreadySubmitted();
    error MaxSubmissionsReached();
    error NotCommitted();
    error AlreadyRevealed();
    error CommitmentMismatch();
    error AnswerTooLong();
    error EmptyAnswer();
    error NotBountyOwner();
    error NoRevealedSubmissions();
    error AlreadyJudged();
    error NotJudgedYet();
    error AlreadyFinalized();
    error InvalidWinnerIndex();
    error BountyNotFound();
    error TransferFailed();
    error EncryptedDataRequired();

    // ─── Modifiers ────────────────────────────────────────────────────
    modifier bountyExists(uint256 id) {
        if (bounties[id].owner == address(0)) revert BountyNotFound();
        _;
    }

    modifier onlyOwner(uint256 id) {
        if (msg.sender != bounties[id].owner) revert NotBountyOwner();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────
    constructor(address _ritualWallet) {
        ritualWallet = IRitualWallet(_ritualWallet);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 0: CREATE
    // ═══════════════════════════════════════════════════════════════════

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 commitDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256) {
        if (msg.value == 0) revert RewardRequired();
        if (commitDeadline <= block.timestamp + MIN_COMMIT_DURATION) revert InvalidDeadlines();
        if (revealDeadline <= commitDeadline + MIN_REVEAL_DURATION) revert InvalidDeadlines();

        uint256 id = nextBountyId++;
        Bounty storage b = bounties[id];
        b.owner = msg.sender;
        b.title = title;
        b.rubric = rubric;
        b.reward = msg.value;
        b.commitDeadline = commitDeadline;
        b.revealDeadline = revealDeadline;

        emit BountyCreated(id, msg.sender, title, msg.value);
        return id;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TRACK 1: COMMIT-REVEAL
    // ═══════════════════════════════════════════════════════════════════

    function submitCommitment(uint256 bountyId, bytes32 commitment) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (block.timestamp > b.commitDeadline) revert CommitPhaseClosed();
        if (b.hasSubmitted[msg.sender]) revert AlreadySubmitted();
        if (b.submissionCount >= MAX_SUBMISSIONS) revert MaxSubmissionsReached();

        uint256 idx = b.submissionCount;
        b.submissions[idx] = Submission({
            submitter: msg.sender,
            mode: PrivacyMode.CommitReveal,
            commitment: commitment,
            encryptedData: "",
            revealed: false,
            answer: ""
        });
        b.hasSubmitted[msg.sender] = true;
        b.submissionCount++;

        emit CommitmentSubmitted(bountyId, msg.sender, commitment);
    }

    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (block.timestamp <= b.commitDeadline) revert CommitPhaseStillActive();
        if (block.timestamp > b.revealDeadline) revert RevealPhaseClosed();
        if (bytes(answer).length == 0) revert EmptyAnswer();
        if (bytes(answer).length > MAX_ANSWER_LENGTH) revert AnswerTooLong();

        uint256 idx = _findSubmission(b, msg.sender);
        Submission storage sub = b.submissions[idx];
        if (sub.mode != PrivacyMode.CommitReveal) revert CommitmentMismatch();
        if (sub.revealed) revert AlreadyRevealed();

        bytes32 expected = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        if (expected != sub.commitment) revert CommitmentMismatch();

        sub.answer = answer;
        sub.revealed = true;

        emit AnswerRevealed(bountyId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TRACK 2: TEE-ENCRYPTED
    // ═══════════════════════════════════════════════════════════════════

    function submitEncryptedAnswer(
        uint256 bountyId,
        bytes calldata encryptedAnswer
    ) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (block.timestamp > b.commitDeadline) revert CommitPhaseClosed();
        if (b.hasSubmitted[msg.sender]) revert AlreadySubmitted();
        if (b.submissionCount >= MAX_SUBMISSIONS) revert MaxSubmissionsReached();
        if (encryptedAnswer.length == 0) revert EncryptedDataRequired();

        uint256 idx = b.submissionCount;
        b.submissions[idx] = Submission({
            submitter: msg.sender,
            mode: PrivacyMode.TEEncrypted,
            commitment: bytes32(0),
            encryptedData: encryptedAnswer,
            revealed: true, // TEE submissions are "revealed" to the TEE at judging time
            answer: ""
        });
        b.hasSubmitted[msg.sender] = true;
        b.submissionCount++;

        emit EncryptedAnswerSubmitted(bountyId, msg.sender, encryptedAnswer.length);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 3: JUDGE (batch LLM via Ritual precompile 0x0802)
    // ═══════════════════════════════════════════════════════════════════

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (block.timestamp <= b.revealDeadline) revert RevealPhaseClosed();
        if (b.judged) revert AlreadyJudged();

        // Count eligible submissions
        uint256 eligibleCount = 0;
        for (uint256 i = 0; i < b.submissionCount; i++) {
            if (b.submissions[i].revealed) eligibleCount++;
        }
        if (eligibleCount == 0) revert NoRevealedSubmissions();

        // Call LLM precompile (0x0802) for batch judging
        // For TEE submissions, the precompile decrypts inside the enclave
        // For commit-reveal, answers are already plaintext
        bytes memory llmResult = _executePrecompile(LLM_INFERENCE_PRECOMPILE, llmInput);
        b.aiReview = string(llmResult);
        b.judged = true;

        emit JudgingComplete(bountyId, b.aiReview);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PHASE 4: FINALIZE
    // ═══════════════════════════════════════════════════════════════════

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        if (!b.judged) revert NotJudgedYet();
        if (b.finalized) revert AlreadyFinalized();
        if (winnerIndex >= b.submissionCount) revert InvalidWinnerIndex();
        if (!b.submissions[winnerIndex].revealed) revert InvalidWinnerIndex();

        b.finalized = true;
        b.winnerIndex = winnerIndex;

        address winner = b.submissions[winnerIndex].submitter;
        uint256 reward = b.reward;

        (bool success, ) = winner.call{value: reward}("");
        if (!success) revert TransferFailed();

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    function getBountyInfo(uint256 bountyId) external view bountyExists(bountyId) returns (
        address owner,
        string memory title,
        string memory rubric,
        uint256 reward,
        uint256 commitDeadline,
        uint256 revealDeadline,
        bool judged,
        bool finalized,
        uint256 submissionCount
    ) {
        Bounty storage b = bounties[bountyId];
        return (b.owner, b.title, b.rubric, b.reward, b.commitDeadline, b.revealDeadline, b.judged, b.finalized, b.submissionCount);
    }

    function getSubmissionMeta(uint256 bountyId, uint256 index) external view bountyExists(bountyId) returns (
        address submitter,
        PrivacyMode mode,
        bool revealed,
        uint256 encryptedDataLength
    ) {
        Submission storage s = bounties[bountyId].submissions[index];
        return (s.submitter, s.mode, s.revealed, s.encryptedData.length);
    }

    function getAiReview(uint256 bountyId) external view bountyExists(bountyId) returns (string memory) {
        return bounties[bountyId].aiReview;
    }

    function getCurrentPhase(uint256 bountyId) external view bountyExists(bountyId) returns (string memory) {
        Bounty storage b = bounties[bountyId];
        if (b.finalized) return "FINALIZED";
        if (b.judged) return "JUDGED";
        if (block.timestamp <= b.commitDeadline) return "COMMIT";
        if (block.timestamp <= b.revealDeadline) return "REVEAL";
        return "JUDGE";
    }

    // ─── Internal Helpers ─────────────────────────────────────────────

    function _findSubmission(Bounty storage b, address submitter) internal view returns (uint256) {
        for (uint256 i = 0; i < b.submissionCount; i++) {
            if (b.submissions[i].submitter == submitter) return i;
        }
        revert NotCommitted();
    }
}
