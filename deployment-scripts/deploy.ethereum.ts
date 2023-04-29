import { ethers, upgrades } from "hardhat";
import { tryVerify } from "./misc/Helpers";
import { config } from "./configs/config.ethereum";

async function main() {
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L1ComptrollerFactory = await ethers.getContractFactory(
        "L1Comptroller"
    );
    
    const L1Comptroller = await upgrades.deployProxy(
        L1ComptrollerFactory,
        [config.L1CrossDomainMessenger, config.MTA, config.CrossChainGasLimit],
        { kind: "transparent" }
    );

    await L1Comptroller.deployed();

    console.log(`L1Comptroller deployed at ${L1Comptroller.address}`);

    await tryVerify(
        hre,
        L1Comptroller.address,
        "src/L1Comptroller.sol:L1Comptroller",
        []
    );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
