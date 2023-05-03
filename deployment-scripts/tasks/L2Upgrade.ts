import { task } from "hardhat/config";

task("L2Upgrade", "Upgrades L2Comptroller contract on Optimism")
    .addParam("proxy", "L2Comptroller proxy contract address")
    .setAction(async (taskArgs) => {
        await hre.run("compile");

        const L2Comptroller = await ethers.getContractFactory("L2Comptroller");

        console.log(
            `Preparing proposal to upgrade contract with proxy ${taskArgs.proxy}...`
        );

        const proposal = await defender.proposeUpgrade(
            taskArgs.proxy,
            L2Comptroller
        );

        console.log("Upgrade proposal created at:", proposal.url);

        // TODO: Verify the new implementation contract.
    });