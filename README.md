<div align="center">

# 🛡️ Privacy-Preserving AI Bounty Judge

### *What if every bounty answer was cryptographically sealed until the judge was ready?*

A dual-track privacy system for on-chain AI bounties via [Ritual Chain](https://ritual.foundation) precompiles. Eliminates plagiarism through commit-reveal cryptography and TEE-encrypted submissions.

<br>

![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-363636?style=for-the-badge&logo=solidity&logoColor=white)
![Ritual](https://img.shields.io/badge/Ritual_Chain-1979-8B5CF6?style=for-the-badge)
![Privacy](https://img.shields.io/badge/Privacy-Commit_Reveal_+_TEE-22C55E?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

<br>

[Architecture](#-architecture) · [Contracts](#-smart-contracts) · [Quick Start](#-quick-start) · [Tests](#-testing)

</div>

---

## 💀 The Problem

Traditional bounty systems expose every answer on-chain in plaintext. Early submissions become visible to everyone.

```
[Alice] → Submits "ZK rollups are superior because..." → [Blockchain (PUBLIC)]
                                                            |
[Bob]   ← Reads Alice's answer from block data ←────────────┘
  |
  └──→ Submits "ZK rollups are superior because... and also..." → [Blockchain]
  
Alice's first-mover advantage → GONE
```

**Every open bounty on EVM has this flaw.**

---

## 🧠 The Solution: Dual Privacy Tracks

### Track 1: Commit-Reveal (Any EVM Chain)
Split submission into two phases. During Phase 1, only an irreversible hash exists on-chain.

```
         PHASE 1: COMMIT                    PHASE 2: REVEAL
    ┌──────────────────────┐           ┌──────────────────────┐
    │                      │           │                      │
    │  Alice → 0x8a3f...   │           │  Alice → "Solidity"  │ ✓ verified
    │  Bob   → 0x1c7e...   │    ───►   │  Bob   → "Rust"      │ ✓ verified
    │  Carol → 0x9b2d...   │           │  Carol → "Cairo"     │ ✓ verified
    │                      │           │                      │
    │  answers: HIDDEN     │           │  answers: REVEALED   │
    └──────────────────────┘           └──────────────────────┘
         ⏰ before deadline                 ⏰ after deadline
```

### Track 2: TEE-Encrypted (Ritual Chain Native)
Answers encrypted via ECIES to executor's public key. Decrypted ONLY inside the TEE enclave during judging.

```
[Submitter] → ECIES(answer, executorPubKey) → [Encrypted Blob On-Chain]
                                                    |
[LLM Precompile] ← Decrypts INSIDE TEE ←───────────┘
                      ↓
              Judges all answers
              (plaintext NEVER leaves enclave)
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Smart Contracts                             │
│                                                                  │
│  ┌─────────────────────┐      ┌─────────────────────────────┐   │
│  │    AIJudge.sol       │      │  PrivacyBountyJudge.sol     │   │
│  │  (Commit-Reveal)     │      │  (Commit-Reveal + TEE)      │   │
│  │                      │      │                             │   │
│  │  submitCommitment()  │      │  submitCommitment()         │   │
│  │  revealAnswer()      │      │  submitEncryptedAnswer()    │   │
│  │  judgeAll()          │      │  revealAnswer()             │   │
│  │  finalizeWinner()    │      │  judgeAll()                 │   │
│  │                      │      │  finalizeWinner()           │   │
│  └─────────────────────┘      └─────────────────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              PrecompileConsumer.sol (utils/)                 │ │
│  │         Handles async LLM precompile (0x0802) calls         │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Ritual Chain (ID 1979)                       │
│                                                                  │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  Contract   │  │ RitualWallet │  │ LLM Precompile (0x0802)│   │
│  │             │  │ (fee mgmt)   │  │ (batch judging in TEE) │   │
│  └────────────┘  └──────────────┘  └────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Lifecycle Flow

| Phase | Function | What Happens | Privacy |
|-------|----------|--------------|---------|
| **1. Create** | `createBounty()` | Owner funds bounty, sets deadlines | Public |
| **2. Commit** | `submitCommitment()` | Hash stored on-chain | 🔒 Hidden |
| **2b. Encrypt** | `submitEncryptedAnswer()` | ECIES blob stored | 🔒 Encrypted |
| **3. Reveal** | `revealAnswer()` | Plaintext + salt verified | 🔓 Revealed |
| **4. Judge** | `judgeAll()` | Batch LLM call via 0x0802 | 🤖 AI decides |
| **5. Finalize** | `finalizeWinner()` | Reward transferred | ✅ Public |

---

## 📜 Smart Contracts

### AIJudge.sol — Required Track
Pure commit-reveal implementation. Works on any EVM chain.

**Key Functions:**
```solidity
// Phase 1: Lock in answer hash
function submitCommitment(uint256 bountyId, bytes32 commitment) external;

// Phase 2: Reveal after commit deadline
function revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt) external;

// Phase 3: Owner triggers AI judging
function judgeAll(uint256 bountyId, bytes calldata llmInput) external;

// Phase 4: Owner confirms winner
function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external;
```

**Security Properties:**
- `keccak256(answer, salt, msg.sender, bountyId)` prevents commitment stealing
- Separate deadlines enforce forced-blind window
- Owner validates AI recommendation before payout
- Max 15 submissions per bounty

### PrivacyBountyJudge.sol — Advanced Track
Dual-mode: supports both commit-reveal AND TEE-encrypted submissions.

**Additional Functions:**
```solidity
// TEE-encrypted submission (Ritual Chain only)
function submitEncryptedAnswer(uint256 bountyId, bytes calldata encryptedAnswer) external;

// View submission metadata without exposing answer
function getSubmissionMeta(uint256 bountyId, uint256 index) external view returns (
    address submitter, PrivacyMode mode, bool revealed, uint256 encryptedDataLength
);
```

**Privacy Properties:**
- ECIES encryption to executor's public key
- Answers NEVER decrypted outside TEE
- `getSubmissionMeta()` returns only submitter + data length (no answer)
- Batch judging in single LLM precompile call

---

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- npm or pnpm

### Install & Compile

```bash
cd hardhat
npm install
npx hardhat compile
```

### Run Tests

```bash
# All tests
npx hardhat test

# Only Solidity tests
npx hardhat test solidity
```

### Deploy to Ritual Chain

```bash
# Set your private key
export DEPLOYER_PRIVATE_KEY="0x..."

# Deploy
npx hardhat run scripts/deploy.ts --network ritual
```

### Network Config

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Ritual Chain | 1979 | `https://rpc.ritualfoundation.org` |
| Explorer | — | https://ritual-scan.xyz |

---

## 🧪 Testing

### Test Coverage

| Category | Test Cases | Coverage |
|----------|------------|----------|
| Create Bounty | Valid params, zero reward, past deadline | ✅ |
| Submit Commitment | Before/after deadline, duplicates, max limit | ✅ |
| Reveal Answer | Correct/wrong answer, timing, double reveal | ✅ |
| TEE Encrypted | Submit encrypted, metadata privacy, duplicates | ✅ |
| Judge | Batch LLM, timing, owner-only | ✅ |
| Finalize | Valid winner, timing, double-finalize | ✅ |

### Key Attack Vectors Tested

| Attack | Mitigation |
|--------|-----------|
| Front-running commitment | Hash includes `msg.sender` |
| Replay across bounties | Hash includes `bountyId` |
| Copying another's commitment | Reveal fails (sender mismatch) |
| Owner judges early | `revealDeadline` check enforced |
| Double-claim reward | `finalized` flag checked |

---

## 🔐 Security Model

### Commit-Reveal Guarantees
- **Commit Phase:** Only `keccak256` hash on-chain → answers invisible
- **Reveal Phase:** Hash verification `keccak256(answer, salt, sender, bountyId) == commitment`
- **Salt:** `bytes32` (2²⁵⁶ space) → brute-force impossible
- **Binding:** `msg.sender` in hash → cannot submit another's commitment

### TEE-Encrypted Guarantees
- **On-chain:** Only ECIES-encrypted blobs stored
- **Off-chain:** Plaintext exists only in submitter's memory
- **TEE:** Decryption + judging inside enclave → no human can read answers
- **Batch:** All submissions judged in single LLM call → efficient + fair comparison

### What's Public vs Hidden

| Data | Visibility | Rationale |
|------|-----------|-----------|
| Bounty title, rubric, reward | 🟢 Public | Transparency |
| Commitment hashes | 🟢 Public | Proves timestamp |
| Encrypted blobs | 🟢 Public | Unreadable without key |
| Answers (commit phase) | 🔴 Hidden | Prevents copying |
| Answers (TEE mode) | 🔴 Hidden | Never leaves TEE |
| AI review | 🟢 Public | Auditability |
| Winner | 🟢 Public | Verifiable outcome |

---

## 🤖 AI vs Human Decisions

In a fair bounty system, **AI should evaluate merit** — comparing submissions against a rubric, scoring depth and correctness, and producing a ranked list with reasoning. **Humans should set the rules** — defining the rubric, choosing deadlines, funding the bounty, and making the final call on the winner. The LLM provides a recommendation; the owner validates and executes. This prevents edge cases where AI misapplies context while maintaining impartial evaluation.

---

## 📁 Project Structure

```
ritual-chain-workshop/
├── hardhat/
│   ├── contracts/
│   │   ├── AIJudge.sol              # Required track: commit-reveal
│   │   ├── PrivacyBountyJudge.sol   # Advanced track: commit-reveal + TEE
│   │   ├── utils/
│   │   │   └── PrecompileConsumer.sol
│   │   └── test/
│   │       └── BountyTest.t.sol     # Foundry unit tests
│   ├── test/
│   │   └── AIJudge.test.ts          # Hardhat integration tests
│   ├── scripts/
│   │   └── deploy.ts                # Deployment script
│   ├── hardhat.config.ts
│   └── package.json
├── web/                             # Frontend (Next.js)
├── README.md
├── ARCHITECTURE.md
└── TEST_PLAN.md
```

---

## 📄 License

MIT
