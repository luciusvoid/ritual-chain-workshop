# Hardhat Project — AI Bounty Judge

Smart contracts for the Privacy-Preserving AI Bounty Judge system.

## Contracts

| File | Track | Description |
|------|-------|-------------|
| `AIJudge.sol` | Required | Commit-reveal bounty judge with LLM precompile integration |
| `PrivacyBountyJudge.sol` | Advanced | Dual-track: commit-reveal + TEE-encrypted submissions |
| `utils/PrecompileConsumer.sol` | Util | Async precompile handler for Ritual Chain |

## Quick Start

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Test Results

```
16 passing — all tests pass ✅
```

### Running Specific Tests

```bash
# Solidity tests only
npx hardhat test solidity

# TypeScript integration tests
npx hardhat test nodejs
```

## Deploy to Ritual Chain

```bash
export DEPLOYER_PRIVATE_KEY="0x..."
npx hardhat run scripts/deploy.ts --network ritual
```

### Network

| Property | Value |
|----------|-------|
| Chain ID | 1979 |
| RPC | `https://rpc.ritualfoundation.org` |
| Token | RITUAL |