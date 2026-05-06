import hre from "hardhat";
import fs from "fs";
import path from "path";

const OWNER = "0xB76E40277B79B78dFa954CBEc863D0e4Fd0656ca";
const INBOX = "0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f";
const DEPLOYMENTS_FILE = path.join(__dirname, "../deployments/mainnet-v2.json");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const L1ComptrollerArbFactory = await hre.ethers.getContractFactory("L1ComptrollerArb");

  const proxy = await hre.upgrades.deployProxy(
    L1ComptrollerArbFactory,
    [OWNER, INBOX],
    { kind: "transparent", initialOwner: OWNER, redeployImplementation: "always" }
  );

  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();
  console.log("L1ComptrollerArb proxy deployed at:", proxyAddress);

  const implAddress = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("Implementation address:", implAddress);

  const proxyAdminAddress = await hre.upgrades.erc1967.getAdminAddress(proxyAddress);
  console.log("ProxyAdmin address:", proxyAdminAddress);

  // Verify ProxyAdmin owner matches expected owner
  const proxyAdmin = await hre.ethers.getContractAt(
    ["function owner() view returns (address)"],
    proxyAdminAddress
  );
  const proxyAdminOwner = await proxyAdmin.owner();
  console.log("ProxyAdmin owner:", proxyAdminOwner);

  if (proxyAdminOwner.toLowerCase() !== OWNER.toLowerCase()) {
    throw new Error(
      `ProxyAdmin owner mismatch! Expected ${OWNER}, got ${proxyAdminOwner}`
    );
  }
  console.log("ProxyAdmin owner verified ✓");

  // Verify implementation on Etherscan
  console.log("Verifying implementation contract...");
  try {
    await hre.run("verify:verify", {
      address: implAddress,
      contract: "src/arb-stack/L1ComptrollerArb.sol:L1ComptrollerArb",
      constructorArguments: [],
    });
    console.log("Implementation verified ✓");
  } catch (e: any) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("Implementation already verified ✓");
    } else {
      console.error("Verification failed:", e.message);
    }
  }

  // Update deployments/mainnet-v2.json
  const deployTx = proxy.deploymentTransaction();
  const proxyTxHash = deployTx?.hash ?? "";

  const deployment = {
    admin: {
      address: proxyAdminAddress,
      txHash: proxyTxHash,
    },
    proxies: [
      {
        address: proxyAddress,
        txHash: proxyTxHash,
        kind: "transparent",
        comptrollerType: "Arbitrum",
        env: "production",
      },
    ],
    impls: [
      {
        address: implAddress,
        txHash: proxyTxHash,
        comptrollerType: "Arbitrum",
        env: "production",
      },
    ],
  };

  fs.writeFileSync(DEPLOYMENTS_FILE, JSON.stringify(deployment, null, 4) + "\n");
  console.log("Updated deployments/mainnet-v2.json ✓");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
