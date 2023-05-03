import { task } from "hardhat/config";

task("L1Upgrade", "Upgrades L1Comptroller contract on Ethereum")
    .addParam("proxy", "L1Comptroller proxy contract address")
    .setAction(async (taskArgs, hre) => {
        await hre.run("compile");
        
        const L1Comptroller = await ethers.getContractFactory("L1Comptroller");

        console.log(
            `Preparing proposal to upgrade contract with proxy ${taskArgs.proxy}...`
        );

        const proposal = await defender.proposeUpgrade(
            taskArgs.proxy,
            L1Comptroller
        );

        console.log("Upgrade proposal created at:", proposal.url);

        // TODO: Verify the new implementation contract.
    });
