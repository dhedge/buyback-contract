// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import {L2Comptroller} from "../../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ClaimAllFuzz is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToClaimAllOnL2_WhenBuyBackFromL1Fails(
        uint256 tokenToBurnAmount
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = 0;
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();

        // Make sure that L2Comptroller doesn't have any buy tokens.
        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount = bound(
            tokenToBurnAmount,
            1 + buyTokenPrice / exchangePrice,
            tokenSupplyBefore
        );

        vm.startPrank(address(L2DomainMessenger));

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerProxy));

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount);

        changePrank(alice);

        buyTokenBalanceOfComptroller = type(uint256).max;

        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        uint256 expectedBuyTokenAmount = (tokenToBurnAmount * exchangePrice) /
            buyTokenPrice;

        L2ComptrollerProxy.claimAll(alice);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount,
            "Alice's claim amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount,
            "Alice's L2 burn amount incorrect"
        );
    }

    function test_ShouldBeAbleToClaimAllCorrectly_AfterPartialClaims(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = 0;
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();

        // Make sure that L2Comptroller doesn't have any buy tokens.
        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(
            tokenToBurnAmount1,
            1 + buyTokenPrice / exchangePrice,
            tokenSupplyBefore / 2
        );

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount2 = bound(
            tokenToBurnAmount2,
            1 + buyTokenPrice / exchangePrice,
            tokenSupplyBefore / 2
        );

        vm.startPrank(address(L2DomainMessenger));

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerProxy));

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(
            alice,
            alice,
            tokenToBurnAmount1 + tokenToBurnAmount2
        );

        changePrank(alice);

        buyTokenBalanceOfComptroller = type(uint256).max;

        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount1 * exchangePrice) /
            buyTokenPrice;

        L2ComptrollerProxy.claim(alice, tokenToBurnAmount1);

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount2 * exchangePrice) /
            buyTokenPrice;

        L2ComptrollerProxy.claimAll(alice);

        assertEq(
            aliceBuyTokenBalanceBefore +
                expectedBuyTokenAmount1 +
                expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller -
                expectedBuyTokenAmount1 -
                expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's claim amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's L2 burn amount incorrect"
        );
    }

    // Testing for correct accounting of claimed and burned tokens in case buybacks have been performed on L2 and L1 by the
    // same address.
    function test_ShouldBeAbleToAccountCorrectly_WhenBuyBackOnL2IsDone_AfterFailedBuyBackFromL1(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenBalanceOfComptroller = 0;

        // Make sure that L2Comptroller has enough buy tokens.
        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(
            tokenToBurnAmount1,
            1 + buyTokenPrice / exchangePrice,
            tokenSupplyBefore
        );

        // Make sure the fuzzer gives amount less than the token supply in case of `tokenToBurn` being the L2 version.
        tokenToBurnAmount2 = bound(
            tokenToBurnAmount2,
            1 + buyTokenPrice / exchangePrice,
            tokenToBurnL2.totalSupply()
        );

        deal(address(tokenToBurnL2), alice, tokenToBurnAmount2);

        vm.startPrank(address(L2DomainMessenger));

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerProxy));

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        changePrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            tokenToBurnAmount2
        );

        buyTokenBalanceOfComptroller = type(uint256).max;

        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // Expected amount for buy back on L2.
        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount2 *
            exchangePrice) / buyTokenPrice;

        L2ComptrollerProxy.buyBack(alice, tokenToBurnAmount2);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount1,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount1,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );

        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            0,
            "Alice's claim amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1,
            "Alice's L2 burn amount incorrect"
        );

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount1 *
            exchangePrice) / buyTokenPrice;

        L2ComptrollerProxy.claimAll(alice);

        assertEq(
            aliceBuyTokenBalanceBefore +
                expectedBuyTokenAmount1 +
                expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount1 - expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount1,
            "Alice's claim amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1,
            "Alice's L2 burn amount incorrect"
        );
    }
}
