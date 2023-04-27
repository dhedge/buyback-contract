// import { ethers, upgrades } from "hardhat";
import { task } from "hardhat/config";

task(
    "L1Handover",
    "Sets L2Comptroller address in L1Comptroller and transfers the ownership of L1 ProxyAdmin to the specified multisig"
)
    .addParam("l1comptroller", "Address of the L1Comptroller")
    .addParam("l2comptroller", "Address of the L2Comptroller")
    .addParam("multisig", "Address of the new owner multisig")
    .setAction(async (taskArgs) => {
        const L1Comptroller = await ethers.getContractAt(
            "L1Comptroller",
            taskArgs.l1comptroller
        );

        console.log(
            `Setting ${taskArgs.l2comptroller} as L2Comptroller in L1Comptroller at ${taskArgs.l1comptroller}...`
        );

        await L1Comptroller.setL2Comptroller(taskArgs.l2comptroller);

        console.log(
            `L2Comptroller set. Transferring ownership to ${taskArgs.multisig}`
        );

        console.log(
            `ProxyAdmin address is ${
                (await upgrades.admin.getInstance()).address
            }`
        );

        await upgrades.admin.transferProxyAdminOwnership(taskArgs.multisig);

        console.log("Ownership transferred successfully");
    });
