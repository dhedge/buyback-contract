import { task } from "hardhat/config";
import { tryVerify } from "../../misc/Helpers";

task("deploy-op-l1comptroller", "Deploys an upgradeable OP-stack flavour L1Comptroller contract")
  .addParam("owner", "The ultimate contract owner")
  .addParam("messenger", "The OP L1 Cross Domain Messenger address (on Ethereum)")
  .addParam("gaslimit", "The cross chain gas limit")
  .setAction(async (taskArgs, hre) => {
    await hre.run("compile");
    
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L1ComptrollerOPV2Factory = await ethers.getContractFactory(
        "L1ComptrollerOPV2"
    );
    
    const L1ComptrollerOPV2 = await upgrades.deployProxy(
      L1ComptrollerOPV2Factory,
        [taskArgs.owner, taskArgs.messenger, taskArgs.gaslimit],
        { kind: "transparent" }
    );

    await L1ComptrollerOPV2.deployed();

    console.log(`L1ComptrollerOPV2 deployed at ${L1ComptrollerOPV2.address}`);

    await tryVerify(
        hre,
        L1ComptrollerOPV2.address,
        "src/op-stack/v2/L1ComptrollerOPV2.sol:L1ComptrollerOPV2",
        []
    );
  });

module.exports = {};