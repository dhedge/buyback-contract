// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ConvertFunctionsV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ConvertToTokenToBuy_ShouldReturnCorrectAmount() public {
        uint256 usdyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        assertEq(
            L2ComptrollerV2Proxy.convertToTokenToBuy(address(MTA_L1), USDy, 100e18),
            usdyExpectedBuyAmount,
            "Incorrect conversion from burn token to buy token"
        );
        assertEq(
            L2ComptrollerV2Proxy.convertToTokenToBuy(address(POTATO_SWAP), USDpy, 100e18),
            usdpyExpectedBuyAmount,
            "Incorrect conversion from burn token to buy token"
        );
    }

    function test_ConvertToTokenToBurn_ShouldReturnCorrectAmount() public {
        uint256 usdyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        // We are ok with rounding error impacting the last 3 digits of the result.
        assertApproxEqAbs(
            L2ComptrollerV2Proxy.convertToTokenToBurn(address(MTA_L1), USDy, usdyExpectedBuyAmount),
            100e18,
            1e3,
            "Incorrect conversion from buy token to burn token"
        );

        assertApproxEqAbs(
            L2ComptrollerV2Proxy.convertToTokenToBurn(address(POTATO_SWAP), USDpy, usdpyExpectedBuyAmount),
            100e18,
            1e3,
            "Incorrect conversion from buy token to burn token"
        );
    }
}
