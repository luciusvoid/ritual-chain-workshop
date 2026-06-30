// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AIJudge} from "../AIJudge.sol";
import {PrivacyBountyJudge} from "../PrivacyBountyJudge.sol";

contract AIJudgeTest is Test {
    AIJudge public judge;
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public carol = address(0x4);
    address public ritualWallet = address(0x999);

    uint256 public constant REWARD = 1 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        judge = new AIJudge(ritualWallet);
    }

    // ─── Create Bounty ────────────────────────────────────────

    function test_createBounty_success() public {
        vm.prank(owner);
        uint256 id = judge.createBounty{value: REWARD}(
            "Best L2", "Depth 50%", block.timestamp + 2 hours, block.timestamp + 4 hours
        );
        assertEq(id, 1);
        (address bOwner, string memory title,,,,,,,) = judge.getBountyInfo(id);
        assertEq(bOwner, owner);
        assertEq(keccak256(bytes(title)), keccak256(bytes("Best L2")));
    }

    function test_createBounty_zeroReward_reverts() public {
        vm.prank(owner);
        vm.expectRevert(AIJudge.RewardRequired.selector);
        judge.createBounty{value: 0}("Title", "Rubric", block.timestamp + 2 hours, block.timestamp + 4 hours);
    }

    function test_createBounty_badDeadline_reverts() public {
        vm.prank(owner);
        vm.expectRevert(AIJudge.InvalidDeadlines.selector);
        judge.createBounty{value: REWARD}("Title", "Rubric", block.timestamp + 10 minutes, block.timestamp + 4 hours);
    }

    // ─── Submit Commitment ────────────────────────────────────

    function _createBounty() internal returns (uint256) {
        vm.prank(owner);
        return judge.createBounty{value: REWARD}(
            "Test", "Rubric", block.timestamp + 2 hours, block.timestamp + 4 hours
        );
    }

    function _makeCommitment(string memory answer, bytes32 salt, address sender, uint256 bountyId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(answer, salt, sender, bountyId));
    }

    function test_submitCommitment_success() public {
        uint256 id = _createBounty();
        bytes32 commitment = _makeCommitment("Solidity", bytes32(uint256(1)), alice, id);
        vm.prank(alice);
        judge.submitCommitment(id, commitment);
        (address submitter,, bool revealed,) = judge.getSubmission(id, 0);
        assertEq(submitter, alice);
        assertFalse(revealed);
    }

    function test_submitCommitment_afterDeadline_reverts() public {
        uint256 id = _createBounty();
        vm.warp(block.timestamp + 3 hours);
        vm.prank(alice);
        vm.expectRevert(AIJudge.CommitPhaseClosed.selector);
        judge.submitCommitment(id, bytes32(uint256(1)));
    }

    function test_submitCommitment_duplicate_reverts() public {
        uint256 id = _createBounty();
        bytes32 c = _makeCommitment("A", bytes32(uint256(1)), alice, id);
        vm.prank(alice);
        judge.submitCommitment(id, c);
        vm.prank(alice);
        vm.expectRevert(AIJudge.AlreadyCommitted.selector);
        judge.submitCommitment(id, bytes32(uint256(2)));
    }

    // ─── Reveal Answer ────────────────────────────────────────

    function test_revealAnswer_success() public {
        uint256 id = _createBounty();
        bytes32 salt = bytes32(uint256(42));
        string memory answer = "Rust is best";
        bytes32 commitment = _makeCommitment(answer, salt, alice, id);

        vm.prank(alice);
        judge.submitCommitment(id, commitment);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(alice);
        judge.revealAnswer(id, answer, salt);

        (,, bool revealed, string memory revealedAnswer) = judge.getSubmission(id, 0);
        assertTrue(revealed);
        assertEq(keccak256(bytes(revealedAnswer)), keccak256(bytes(answer)));
    }

    function test_revealAnswer_wrongSalt_reverts() public {
        uint256 id = _createBounty();
        bytes32 salt = bytes32(uint256(42));
        bytes32 commitment = _makeCommitment("Answer", salt, alice, id);

        vm.prank(alice);
        judge.submitCommitment(id, commitment);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.prank(alice);
        vm.expectRevert(AIJudge.CommitmentMismatch.selector);
        judge.revealAnswer(id, "Answer", bytes32(uint256(99)));
    }

    function test_revealAnswer_duringCommitPhase_reverts() public {
        uint256 id = _createBounty();
        bytes32 salt = bytes32(uint256(1));
        bytes32 commitment = _makeCommitment("A", salt, alice, id);
        vm.prank(alice);
        judge.submitCommitment(id, commitment);

        vm.prank(alice);
        vm.expectRevert(AIJudge.CommitPhaseStillActive.selector);
        judge.revealAnswer(id, "A", salt);
    }

    // ─── Get Current Phase ────────────────────────────────────

    function test_getCurrentPhase() public {
        uint256 id = _createBounty();
        assertEq(judge.getCurrentPhase(id), "COMMIT");
    }

    // ─── Finalize ─────────────────────────────────────────────

    function test_finalize_beforeJudge_reverts() public {
        uint256 id = _createBounty();
        vm.prank(owner);
        vm.expectRevert(AIJudge.NotJudgedYet.selector);
        judge.finalizeWinner(id, 0);
    }
}

contract PrivacyBountyJudgeTest is Test {
    PrivacyBountyJudge public judge;
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public ritualWallet = address(0x999);

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 10 ether);
        judge = new PrivacyBountyJudge(ritualWallet);
    }

    function _createBounty() internal returns (uint256) {
        vm.prank(owner);
        return judge.createBounty{value: 1 ether}(
            "TEE Test", "Rubric", block.timestamp + 2 hours, block.timestamp + 4 hours
        );
    }

    function test_submitEncryptedAnswer_success() public {
        uint256 id = _createBounty();
        bytes memory encrypted = abi.encodePacked("encrypted_data_here");
        vm.prank(alice);
        judge.submitEncryptedAnswer(id, encrypted);
        (address submitter, PrivacyBountyJudge.PrivacyMode mode, bool revealed, uint256 dataLen) = judge.getSubmissionMeta(id, 0);
        assertEq(submitter, alice);
        assertTrue(mode == PrivacyBountyJudge.PrivacyMode.TEEncrypted);
        assertTrue(revealed);
        assertEq(dataLen, encrypted.length);
    }

    function test_submitEncryptedAnswer_duplicate_reverts() public {
        uint256 id = _createBounty();
        vm.prank(alice);
        judge.submitEncryptedAnswer(id, "data1");
        vm.prank(alice);
        vm.expectRevert(PrivacyBountyJudge.AlreadySubmitted.selector);
        judge.submitEncryptedAnswer(id, "data2");
    }

    function test_submitEncryptedAnswer_empty_reverts() public {
        uint256 id = _createBounty();
        vm.prank(alice);
        vm.expectRevert(PrivacyBountyJudge.EncryptedDataRequired.selector);
        judge.submitEncryptedAnswer(id, "");
    }

    function test_getSubmissionMeta_noAnswerExposed() public {
        uint256 id = _createBounty();
        vm.prank(alice);
        judge.submitEncryptedAnswer(id, "secret_encrypted_data");
        (,, bool revealed, uint256 dataLen) = judge.getSubmissionMeta(id, 0);
        assertTrue(revealed);
        assertEq(dataLen, 21);
        // Note: answer is NOT exposed via getSubmissionMeta
    }

    function test_finalize_beforeJudge_reverts() public {
        uint256 id = _createBounty();
        vm.prank(owner);
        vm.expectRevert(PrivacyBountyJudge.NotJudgedYet.selector);
        judge.finalizeWinner(id, 0);
    }
}
