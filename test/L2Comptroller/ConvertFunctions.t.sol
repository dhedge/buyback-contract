// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2Comptroller} from "../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ConvertFunctions is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ConvertToTokenToBuy_ShouldReturnCorrectAmount() public {
        uint256 expectedBuyTokenAmount = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        assertEq(
            L2ComptrollerProxy.convertToTokenToBuy(100e18),
            expectedBuyTokenAmount,
            "Incorrect conversion from burn token to buy token"
        );
    }

    function test_ConvertToTokenToBurn_ShouldReturnCorrectAmount() public {
        uint256 buyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) /
            tokenToBuy.tokenPrice();

        // We are ok with rounding error impacting the last 3 digits of the result.
        assertApproxEqAbs(
            L2ComptrollerProxy.convertToTokenToBurn(buyTokenAmount),
            100e18,
            1e3,
            "Incorrect conversion from buy token to burn token"
        );
    }
}
