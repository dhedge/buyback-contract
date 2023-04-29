// import { ethers, upgrades } from "hardhat";
import { task } from "hardhat/config";

task(
    "L2Handover",
    "Sets L1Comptroller address in L2Comptroller and transfers the ownership of L2 ProxyAdmin to the specified multisig"
)
    .addParam("l1comptroller", "Address of the L1Comptroller")
    .addParam("l2comptroller", "Address of the L2Comptroller")
    .addParam("multisig", "Address of the new owner multisig")
    .setAction(async (taskArgs) => {
        const L2Comptroller = await ethers.getContractAt(
            "L2Comptroller",
            taskArgs.l2comptroller
        );

        console.log(
            `Setting ${taskArgs.l1comptroller} as L1Comptroller in L2Comptroller at ${taskArgs.l2comptroller}...`
        );

        // If L1Comptroller is not set by the owner then set it.
        if (
            (await L2Comptroller.L1Comptroller()) ===
            ethers.constants.AddressZero
        )
            await L2Comptroller.setL1Comptroller(taskArgs.l1comptroller);

        console.log(
            `L1Comptroller set. Transferring ownership to ${taskArgs.multisig}`
        );

        console.log(
            `ProxyAdmin address is ${
                (await upgrades.admin.getInstance()).address
            }`
        );

        await upgrades.admin.transferProxyAdminOwnership(taskArgs.multisig);

        console.log(
            `Ownership transferred successfully to ${taskArgs.multisig}`
        );
    });
