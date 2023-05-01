import { tryVerify } from "./misc/Helpers";
import { config } from "./configs/config.optimism";

async function main() {
    const signer = (await ethers.getSigners())[0];
    console.log("Deployer: ", signer.address);

    const L2ComptrollerFactory = await ethers.getContractFactory(
        "L2Comptroller"
    );

    const L2Comptroller = await upgrades.deployProxy(
        L2ComptrollerFactory,
        [
            config.L2CrossDomainMessenger,
            config.MTA,
            config.MTy,
            config.OptimismMultisig,
            config.ExchangePrice,
            config.MaxTokenPriceDrop,
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
