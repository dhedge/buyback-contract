import hre from "hardhat";
import fs from "fs";
import path from "path";

const OWNER = "0x13471A221D6A346556723842A1526C603Dc4d36B";
const DEPLOYMENTS_FILE = path.join(__dirname, "../deployments/arbitrum-v2.json");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const L2ComptrollerArbFactory = await hre.ethers.getContractFactory("L2ComptrollerArb");

  const proxy = await hre.upgrades.deployProxy(
    L2ComptrollerArbFactory,
    [OWNER],
    { kind: "transparent", initialOwner: OWNER }
  );

  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();
  console.log("L2ComptrollerArb proxy deployed at:", proxyAddress);

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

  // Verify implementation on Etherscan/Arbiscan
  console.log("Verifying implementation contract...");
  try {
    await hre.run("verify:verify", {
      address: implAddress,
      contract: "src/arb-stack/L2ComptrollerArb.sol:L2ComptrollerArb",
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

  // Update deployments/arbitrum-v2.json
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
        env: "production",
      },
    ],
    impls: [
      {
        address: implAddress,
        txHash: proxyTxHash,
        env: "production",
      },
    ],
  };

  fs.writeFileSync(DEPLOYMENTS_FILE, JSON.stringify(deployment, null, 4) + "\n");
  console.log("Updated deployments/arbitrum-v2.json ✓");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
