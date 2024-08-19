import { expect } from "chai";
import { task } from "hardhat/config";
import { config } from "../configs/v1/config.optimism";

task(
    "CheckL2Comptroller",
    "Checks the L2Comptroller deployment and whether it's ready for use"
)
    .addParam("l2comptroller", "The L2Comptroller deployment to be checked")
    .setAction(async (taskArgs) => {
        const L2Comptroller = await ethers.getContractAt(
            "L2Comptroller",
            taskArgs.l2comptroller
        );

        // Slot value for `_initialized` variable.
        const slotData = await L2Comptroller.provider.getStorageAt(
            taskArgs.l2comptroller,
            0
        );
        const initialized = ethers.BigNumber.from(slotData).and(
            ethers.BigNumber.from("0xff")
        );

        // Here '1' indicates true.
        expect(initialized.toString()).to.equal("1", "Contract uninitialized");
        expect(await L2Comptroller.L1Comptroller()).to.not.equal(
            ethers.constants.AddressZero,
            "L1Comptroller not set"
        );
        expect((await L2Comptroller.crossDomainMessenger()).toLowerCase()).to.equal(
            config.L2CrossDomainMessenger.toLowerCase(),
            "L2CrossDomainMessenger incorrect"
        );
        expect((await L2Comptroller.tokenToBurn()).toLowerCase()).to.equal(
            config.MTA.toLowerCase(),
            "tokenToBurn not set to MTA token"
        );
        expect((await L2Comptroller.tokenToBuy()).toLowerCase()).to.equal(
            config.MTy.toLowerCase(),
            "tokenToBuy not set to MTy token"
        );
        expect((await L2Comptroller.exchangePrice()).toString()).to.equal(
            config.ExchangePrice.toString(),
            "Exchange price incorrect"
        );
        expect((await L2Comptroller.maxTokenPriceDrop()).toString()).to.equal(
            config.MaxTokenPriceDrop.toString(),
            "Max token price drop incorrect"
        );

        console.log("All checks passed successfully!");
    });
