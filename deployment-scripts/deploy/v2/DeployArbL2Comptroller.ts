import { task } from "hardhat/config";
import { tryVerify } from "../../misc/Helpers";

task("deploy-arb-l2comptroller", "Deploys an upgradeable Arbitrum flavour L2Comptroller contract")
  .addParam("owner", "The ultimate contract owner")
  .setAction(async (taskArgs, hre) => {
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L2ComptrollerArbFactory = await ethers.getContractFactory(
        "L2ComptrollerArb"
    );
    
    const L2ComptrollerArb = await upgrades.deployProxy(
        L2ComptrollerArbFactory,
        [taskArgs.owner],
        { kind: "transparent" }
    );

    await L2ComptrollerArb.deployed();

    console.log(`L1ComptrollerArb deployed at ${L2ComptrollerArb.address}`);

    await tryVerify(
        hre,
        L2ComptrollerArb.address,
        "src/arb-stack/L2ComptrollerArb.sol:L2ComptrollerArb",
        []
    );
  });

module.exports = {};