import { ethers, upgrades } from "hardhat";
import { tryVerify } from "./misc/Helpers";

async function main() {
    const L2CrossDomainMessenger = "0x4200000000000000000000000000000000000007";
    const tokenToBurn = "0x929B939f8524c3Be977af57A4A0aD3fb1E374b50";
    const tokenToBuy = "0x0f6eae52ae1f94bc759ed72b201a2fdb14891485"; // mStable Treasury Yield (https://app.dhedge.org/vault/0x0f6eae52ae1f94bc759ed72b201a2fdb14891485)
    const optimismMultisig = "0x352Fb838A3ae9b0ef2f0EBF24191AcAf4aB9EcEc"; // Used for burning MTA on Optimism.
    const exchangePrice = ethers.utils.parseUnits("3", 16); // $0.03
    const maxTokenPriceDrop = 10; // 10:10000 => 0.1% max price drop acceptable

    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L2ComptrollerFactory = await ethers.getContractFactory(
        "L2Comptroller"
    );

    const L2Comptroller = await upgrades.deployProxy(
        L2ComptrollerFactory,
        [
            L2CrossDomainMessenger,
            tokenToBurn,
            tokenToBuy,
            optimismMultisig,
            exchangePrice,
            maxTokenPriceDrop,
        ],
        { kind: "transparent" }
    );

    await L2Comptroller.deployed();

    console.log(`L2Comptroller deployed at ${L2Comptroller.address}`);

    await tryVerify(
        hre,
        L2Comptroller.address,
        "src/L2Comptroller.sol:L2Comptroller",
        []
    );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
