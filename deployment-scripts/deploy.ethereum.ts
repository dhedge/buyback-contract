import { ethers, upgrades } from "hardhat";
import { tryVerify } from "./misc/Helpers";

async function main() {
    const L1CrossDomainMessenger = "0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1";
    const tokenToBurn = "0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2";
    const crossChainGasLimit = 1920000;

    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L1ComptrollerFactory = await ethers.getContractFactory(
        "L1Comptroller"
    );
    const L1Comptroller = await upgrades.deployProxy(
        L1ComptrollerFactory,
        [L1CrossDomainMessenger, tokenToBurn, crossChainGasLimit],
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
