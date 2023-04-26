// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2Comptroller} from "../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract MaxBurnAmountClaimable is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldReturnCorrectAmount_WhenNoBuyTokenBalance() public {
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        assertEq(
            0,
            L2ComptrollerProxy.maxBurnAmountClaimable(),
            "Incorrect conversion from burn token to buy token"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenNonZeroBuyTokenBalance()
        public
    {
        uint256 buyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) /
            tokenToBuy.tokenPrice();

        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenAmount);

        // We are ok with rounding error impacting the last 3 digits of the result.
        assertApproxEqAbs(
            L2ComptrollerProxy.maxBurnAmountClaimable(),
            100e18,
            1e3,
            "Incorrect max amount claimable"
        );
    }
}
