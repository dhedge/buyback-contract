// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1ComptrollerOPV1} from "../../../src/op-stack/v1/L1ComptrollerOPV1.sol";
import {L2ComptrollerOPV1} from "../../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBack is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToBuyback_WhenReceiverIsSender() public {
        uint256 aliceBurnTokenBalanceBefore = tokenToBurnL2.balanceOf(alice);
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(burnMultiSig);
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(alice, 100e18);
        uint256 expectedBuyTokenAmount = (100e18 * exchangePrice) / buyTokenPrice;

        assertEq(
            tokenToBurnL2.balanceOf(burnMultiSig),
            burnMultiSigBalanceBefore + 100e18,
            "Wrong balance of burn multisig"
        );

        assertEq(
            tokenToBurnL2.balanceOf(alice),
            aliceBurnTokenBalanceBefore - 100e18,
            "Wrong tokenToBurn balance of Alice"
        );
        assertEq(buyTokenAmount, expectedBuyTokenAmount, "Wrong calculation after buyback");
        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Wrong buy token amount received"
        );
    }

    function test_ShouldBeAbleToBuyback_WhenReceiverIsNotSender() public {
        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 aliceBurnTokenBalanceBefore = tokenToBurnL2.balanceOf(alice);
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(burnMultiSig);
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(dummyReceiver, 100e18);
        uint256 expectedBuyTokenAmount = (100e18 * exchangePrice) / buyTokenPrice;

        assertEq(
            tokenToBurnL2.balanceOf(burnMultiSig),
            burnMultiSigBalanceBefore + 100e18,
            "Wrong balance of burn multisig"
        );

        assertEq(
            tokenToBurnL2.balanceOf(alice),
            aliceBurnTokenBalanceBefore - 100e18,
            "Wrong tokenToBurn balance of Alice"
        );
        assertEq(buyTokenAmount, expectedBuyTokenAmount, "Wrong calculation after buyback");
        assertEq(expectedBuyTokenAmount, tokenToBuy.balanceOf(dummyReceiver), "Wrong buy token amount received");
        assertEq(aliceBuyTokenBalanceBefore, tokenToBuy.balanceOf(alice), "Alice shouldn't have received buy tokens");
    }

    function test_ShouldUpdateBuyTokenPrice_WhenLastUpdatedPriceIsLower() public {
        uint256 latestTokenToBuyPrice = L2ComptrollerProxy.lastTokenToBuyPrice();

        uint256 modifiedTokenPrice = latestTokenToBuyPrice + 1e6;

        vm.mockCall(address(tokenToBuy), abi.encodeWithSignature("tokenPrice()"), abi.encode(modifiedTokenPrice));

        assertEq(tokenToBuy.tokenPrice(), modifiedTokenPrice, "Token price not modified");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        L2ComptrollerProxy.buyBack(alice, 100e18);

        assertEq(L2ComptrollerProxy.lastTokenToBuyPrice(), modifiedTokenPrice, "Latest buy token price changed");
    }

    function test_ShouldNotUpdateBuyTokenPrice_WhenLastUpdatedPriceIsHigher() public {
        uint256 latestTokenToBuyPrice = L2ComptrollerProxy.lastTokenToBuyPrice();

        uint256 modifiedTokenPrice = latestTokenToBuyPrice - 1e6;

        vm.mockCall(address(tokenToBuy), abi.encodeWithSignature("tokenPrice()"), abi.encode(modifiedTokenPrice));

        assertEq(tokenToBuy.tokenPrice(), modifiedTokenPrice, "Token price not modified");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        L2ComptrollerProxy.buyBack(alice, 100e18);

        assertEq(L2ComptrollerProxy.lastTokenToBuyPrice(), latestTokenToBuyPrice, "Latest buy token price changed");
    }

    function test_Revert_WhenNotEnoughBurnTokensWithUser() public {
        uint256 aliceBurnTokenBalanceBefore = tokenToBurnL2.balanceOf(alice);

        vm.startPrank(alice);

        // Approve infinite MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), type(uint256).max);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        L2ComptrollerProxy.buyBack(alice, aliceBurnTokenBalanceBefore + 1);

        // Testing if specifying another receiver address doesn't magically enable some transfer to happen.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        L2ComptrollerProxy.buyBack(makeAddr("dummyReceiver"), aliceBurnTokenBalanceBefore + 1);
    }

    function test_Revert_WhenNotEnoughBuyTokensInL2Comptroller() public {
        vm.startPrank(alice);

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }

    function test_Revert_WhenNoBuyTokensInL2Comptroller() public {
        vm.startPrank(alice);

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }

    function test_Revert_WhenBuyTokenPriceLow() public {
        uint256 currentTokenPrice = tokenToBuy.tokenPrice();
        uint256 newTokenPrice = currentTokenPrice - ((currentTokenPrice * uint256(11)) / uint256(10000)); // 0.11% deviation

        // Mocking the token price call of `tokenToBuy` such that it returns a low price.
        vm.mockCall(address(tokenToBuy), abi.encodeWithSignature("tokenPrice()"), abi.encode(newTokenPrice));

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerOPV1.PriceDropExceedsLimit.selector,
                currentTokenPrice - ((currentTokenPrice * L2ComptrollerProxy.maxTokenPriceDrop()) / 10_000),
                newTokenPrice
            )
        );

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }

    function test_Revert_WhenInternalBuybackFunctionCalledByAExternalCaller() public {
        vm.expectRevert(abi.encodeWithSelector(L2ComptrollerOPV1.ExternalCallerNotAllowed.selector));

        vm.prank(alice);

        L2ComptrollerProxy._buyBack(alice, 100e18);
    }
}
