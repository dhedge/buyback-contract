import { task } from "hardhat/config";
import { tryVerify } from "../../misc/Helpers";

task("deploy-op-l2comptroller", "Deploys an upgradeable OP-stack flavour L2Comptroller contract")
  .addParam("owner", "The ultimate contract owner")
  .addParam("messenger", "The OP L2 Cross Domain Messenger address on the L2 network")
  .setAction(async (taskArgs, hre) => {
    await hre.run("compile");
    
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L2ComptrollerOPV2Factory = await ethers.getContractFactory(
        "L2ComptrollerOPV2"
    );
    
    const L2ComptrollerOPV2 = await upgrades.deployProxy(
        L2ComptrollerOPV2Factory,
        [taskArgs.owner, taskArgs.messenger],
        { kind: "transparent" }
    );

    await L2ComptrollerOPV2.deployed();

    console.log(`L2ComptrollerOPV2 deployed at ${L2ComptrollerOPV2.address}`);

    await tryVerify(
        hre,
        L2ComptrollerOPV2.address,
        "src/op-stack/v2/L2ComptrollerOPV2.sol:L2ComptrollerOPV2",
        []
    );
  });

module.exports = {};