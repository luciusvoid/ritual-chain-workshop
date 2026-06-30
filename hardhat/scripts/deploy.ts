import { createWalletClient, createPublicClient, http, defineChain } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import { join } from "path";

const ritualChain = defineChain({
  id: 1979,
  name: "Ritual Chain",
  nativeCurrency: { name: "RITUAL", symbol: "RITUAL", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.ritualfoundation.org"] } },
});

function loadArtifact(name: string) {
  const raw = readFileSync(join(process.cwd(), "artifacts", "contracts", name), "utf-8");
  return JSON.parse(raw);
}

async function main() {
  const pk = process.env.DEPLOYER_PRIVATE_KEY;
  if (!pk) throw new Error("Set DEPLOYER_PRIVATE_KEY");

  const account = privateKeyToAccount(pk as `0x${string}`);
  const client = createWalletClient({ account, chain: ritualChain, transport: http() });
  const publicClient = createPublicClient({ chain: ritualChain, transport: http() });

  console.log(`🔑 Deployer: ${account.address}`);
  const balance = await publicClient.getBalance({ address: account.address });
  console.log(`💰 Balance: ${Number(balance) / 1e18} RITUAL\n`);

  const ritualWalletAddr = "0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948" as const;

  // Deploy AIJudge
  console.log("📦 Deploying AIJudge...");
  const aiJudgeArtifact = loadArtifact("AIJudge.sol/AIJudge.json");

  const aiJudgeHash = await client.deployContract({
    abi: aiJudgeArtifact.abi,
    bytecode: aiJudgeArtifact.bytecode as `0x${string}`,
    args: [ritualWalletAddr],
  });
  console.log(`   TX: ${aiJudgeHash}`);
  const aiJudgeReceipt = await publicClient.waitForTransactionReceipt({ hash: aiJudgeHash });
  console.log(`   ✅ AIJudge: ${aiJudgeReceipt.contractAddress}\n`);

  // Deploy PrivacyBountyJudge
  console.log("📦 Deploying PrivacyBountyJudge...");
  const privacyArtifact = loadArtifact("PrivacyBountyJudge.sol/PrivacyBountyJudge.json");

  const privacyHash = await client.deployContract({
    abi: privacyArtifact.abi,
    bytecode: privacyArtifact.bytecode as `0x${string}`,
    args: [ritualWalletAddr],
  });
  console.log(`   TX: ${privacyHash}`);
  const privacyReceipt = await publicClient.waitForTransactionReceipt({ hash: privacyHash });
  console.log(`   ✅ PrivacyBountyJudge: ${privacyReceipt.contractAddress}\n`);

  console.log("🎉 Deployment complete!");
  console.log(`\n📋 Summary:`);
  console.log(`   AIJudge:            ${aiJudgeReceipt.contractAddress}`);
  console.log(`   PrivacyBountyJudge: ${privacyReceipt.contractAddress}`);
  console.log(`\n🔗 Explorer: https://ritual-scan.xyz/address/${aiJudgeReceipt.contractAddress}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
