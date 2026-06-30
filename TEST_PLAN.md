# Test Plan — Privacy-Preserving AI Bounty Judge

## Overview

This document outlines the testing strategy for both `AIJudge.sol` (Required Track) and `PrivacyBountyJudge.sol` (Advanced Track).

---

## AIJudge.sol — Commit-Reveal Tests

### Phase 1: Create Bounty

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 1 | Create with valid params + reward | Returns bountyId=1, event emitted |
| 2 | Create with zero reward | Reverts: `RewardRequired` |
| 3 | Create with commit deadline in past | Reverts: `InvalidDeadlines` |
| 4 | Create with reveal deadline before commit + 30min | Reverts: `InvalidDeadlines` |
| 5 | Multiple bounties | Sequential IDs (1, 2, 3...) |

### Phase 2: Submit Commitment

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 6 | Valid commitment before deadline | Stored, event emitted |
| 7 | Submit after commit deadline | Reverts: `CommitPhaseClosed` |
| 8 | Same address submits twice | Reverts: `AlreadyCommitted` |
| 9 | Max submissions (15) reached | Reverts: `MaxSubmissionsReached` |
| 10 | Non-existent bounty | Reverts: `BountyNotFound` |

### Phase 3: Reveal Answer

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 11 | Valid reveal (correct answer + salt) | Answer stored, `revealed=true` |
| 12 | Wrong salt | Reverts: `CommitmentMismatch` |
| 13 | Wrong answer | Reverts: `CommitmentMismatch` |
| 14 | Reveal during commit phase | Reverts: `CommitPhaseStillActive` |
| 15 | Reveal after reveal deadline | Reverts: `RevealPhaseClosed` |
| 16 | Double reveal | Reverts: `AlreadyRevealed` |
| 17 | Empty answer | Reverts: `EmptyAnswer` |
| 18 | Answer > 4000 chars | Reverts: `AnswerTooLong` |
| 19 | Reveal without commitment | Reverts: `NotCommitted` |

### Phase 4: Judge

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 20 | Owner calls judgeAll after reveal deadline | AI review stored, `judged=true` |
| 21 | Non-owner calls judgeAll | Reverts: `NotBountyOwner` |
| 22 | Judge before reveal deadline | Reverts: `RevealPhaseClosed` |
| 23 | Double judge | Reverts: `AlreadyJudged` |
| 24 | Judge with no reveals | Reverts: `NoRevealedSubmissions` |

### Phase 5: Finalize

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 25 | Valid finalize after judge | Reward transferred, event emitted |
| 26 | Finalize before judge | Reverts: `NotJudgedYet` |
| 27 | Double finalize | Reverts: `AlreadyFinalized` |
| 28 | Invalid winner index | Reverts: `InvalidWinnerIndex` |
| 29 | Unrevealed winner index | Reverts: `InvalidWinnerIndex` |

---

## PrivacyBountyJudge.sol — Advanced Track Tests

### TEE-Encrypted Submissions

| # | Test Case | Expected Result |
|---|-----------|----------------|
| 30 | Submit encrypted answer | Stored, `mode=TEEncrypted`, `revealed=true` |
| 31 | Duplicate encrypted submission | Reverts: `AlreadySubmitted` |
| 32 | Empty encrypted data | Reverts: `EncryptedDataRequired` |
| 33 | Metadata query hides answer | `getSubmissionMeta` returns length only |
| 34 | Mix commit-reveal + TEE in same bounty | Both modes coexist, separate tracking |
| 35 | Finalize before judge | Reverts: `NotJudgedYet` |

---

## Security Invariant Tests

| # | Invariant | Verification |
|---|-----------|-------------|
| S1 | Commitment = keccak256(answer, salt, sender, bountyId) | Hash mismatch reverts |
| S2 | msg.sender binding | Cannot replay another's commitment |
| S3 | bountyId binding | Cannot replay across bounties |
| S4 | Temporal ordering | Commit → Reveal → Judge → Finalize enforced |
| S5 | Owner-only actions | judgeAll, finalizeWinner restricted |
| S6 | Single payout | finalized flag prevents double-claim |
| S7 | TEE metadata privacy | getSubmissionMeta never exposes answer |

---

## Integration Test Scenarios

### Scenario 1: Full Commit-Reveal Lifecycle
1. Owner creates bounty with 1 ETH reward
2. Alice, Bob, Carol submit commitments
3. Time passes past commit deadline
4. Alice and Bob reveal (Carol forgets)
5. Time passes past reveal deadline
6. Owner calls judgeAll
7. Owner finalizes Alice as winner
8. Alice receives 1 ETH

### Scenario 2: TEE-Encrypted Lifecycle
1. Owner creates bounty
2. Alice submits encrypted answer
3. Bob submits via commit-reveal
4. Both revealed after deadlines
5. Owner judges (batch LLM call)
6. Owner finalizes winner

### Scenario 3: Attack — Commitment Stealing
1. Alice submits commitment C = keccak256("answer", salt, alice, 1)
2. Bob sees C on-chain, submits same C
3. Bob's submission succeeds (different sender, different hash)
4. Bob cannot reveal (doesn't know salt or original answer)
5. Bob's reveal fails: `CommitmentMismatch`
