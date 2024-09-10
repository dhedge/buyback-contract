import { task } from "hardhat/config";
import { tryVerify } from "../../misc/Helpers";

task("deploy-arb-l1comptroller", "Deploys an upgradeable Arbitrum flavour L1Comptroller contract")
  .addParam("owner", "The ultimate contract owner")
  .addParam("inbox", "The Arbitrum stack inbox address")
  .setAction(async (taskArgs, hre) => {
    await hre.run("compile");
    
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L1ComptrollerArbFactory = await ethers.getContractFactory(
        "L1ComptrollerArb"
    );
    
    const L1ComptrollerArb = await upgrades.deployProxy(
        L1ComptrollerArbFactory,
        [taskArgs.owner, taskArgs.inbox],
        { kind: "transparent" }
    );

    await L1ComptrollerArb.deployed();

    console.log(`L1ComptrollerArb deployed at ${L1ComptrollerArb.address}`);

    await tryVerify(
        hre,
        L1ComptrollerArb.address,
        "src/arb-stack/L1ComptrollerArb.sol:L1ComptrollerArb",
        []
    );
  });

module.exports = {};