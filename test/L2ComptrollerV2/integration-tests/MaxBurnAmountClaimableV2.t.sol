// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract MaxBurnAmountClaimableV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldReturnCorrectAmount_WhenNoBuyTokenBalance() public {
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        assertEq(
            0,
            L2ComptrollerV2Proxy.maxBurnAmountClaimable(address(MTA_L1), USDy),
            "Incorrect conversion from burn token to buy token"
        );
        assertEq(
            0,
            L2ComptrollerV2Proxy.maxBurnAmountClaimable(address(POTATO_SWAP), USDpy),
            "Incorrect conversion from burn token to buy token"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenNonZeroBuyTokenBalance() public {
        uint256 usdyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        deal(address(USDy), address(L2ComptrollerV2Proxy), usdyExpectedBuyAmount);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), usdpyExpectedBuyAmount);

        // We are ok with rounding error impacting the last 3 digits of the result.
        assertApproxEqAbs(
            L2ComptrollerV2Proxy.maxBurnAmountClaimable(address(MTA_L1), USDy),
            100e18,
            1e3,
            "Incorrect max amount claimable"
        );
        assertApproxEqAbs(
            L2ComptrollerV2Proxy.maxBurnAmountClaimable(address(POTATO_SWAP), USDpy),
            100e18,
            1e3,
            "Incorrect max amount claimable"
        );
    }
}
