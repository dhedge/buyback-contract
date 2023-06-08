import { expect } from "chai";
import { task } from "hardhat/config";
import { config } from "../configs/config.ethereum";

task(
    "CheckL1Comptroller",
    "Checks the L1Comptroller deployment and whether it's ready for use"
)
    .addParam("l1comptroller", "The L1Comptroller deployment to be checked")
    .setAction(async (taskArgs) => {
        const L1Comptroller = await ethers.getContractAt(
            "L1Comptroller",
            taskArgs.l1comptroller
        );

        // Slot value for `_initialized` variable.
        const slotData0 = await L1Comptroller.provider.getStorageAt(
            taskArgs.l1comptroller,
            0
        );
        const initialized = ethers.BigNumber.from(slotData0).and(
            ethers.BigNumber.from("0xff")
        );

        expect(initialized.toString()).to.equal("1");
        expect(await L1Comptroller.l2Comptroller()).to.not.equal(
            ethers.constants.AddressZero,
            "L2Comptroller not set"
        );
        expect((await L1Comptroller.tokenToBurn()).toLowerCase()).to.equal(
            config.MTA.toLowerCase(),
            "tokenToBurn (MTA) incorrect"
        );
        expect((await L1Comptroller.crossDomainMessenger()).toLowerCase()).to.equal(
            config.L1CrossDomainMessenger.toLowerCase(),
            "L1CrossDomainMessenger address incorrect"
        );

        // Slot data for slot containing the `crossChainGasLimit` variable.
        const slotData153 = await L1Comptroller.provider.getStorageAt(
            taskArgs.l1comptroller,
            153
        );
        const slotData153BigNumber = ethers.BigNumber.from(slotData153);
        const crossChainGasLimit = slotData153BigNumber
            .shr(160)
            .and(ethers.BigNumber.from("0xffffffff"));

        expect(crossChainGasLimit.toString()).to.equal(
            config.CrossChainGasLimit.toString(),
            "Cross chain gas limit incorrect"
        );

        console.log("All checks passed successfully!");
    });
