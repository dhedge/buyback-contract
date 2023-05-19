// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import {L2Comptroller} from "../../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackFromL1Fuzz is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1_WhenSenderIsReceiver(
        uint256 tokenToBurnAmount
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );
        
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1_WhenSenderIsNotReceiver(
        uint256 tokenToBurnAmount
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 dummyReceiverBuyTokenBalanceBefore = tokenToBuy.balanceOf(
            dummyReceiver
        );
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(
            alice,
            dummyReceiver,
            tokenToBurnAmount
        );

        assertEq(
            dummyReceiverBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(dummyReceiver),
            "Buy token balance of dummy receiver incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    // NOTE: An invariant test would be more suitable compared to this kind of fuzzing.
    function testFuzz_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenEnoughBuyTokensOnL2(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

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

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount1 * exchangePrice) /
            buyTokenPrice;

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        // First buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount2 * exchangePrice) /
            buyTokenPrice;

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(
            alice,
            alice,
            tokenToBurnAmount1 + tokenToBurnAmount2
        );

        assertEq(
            aliceBuyTokenBalanceBefore +
                expectedBuyTokenAmount1 +
                expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller -
                expectedBuyTokenAmount1 -
                expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNotEnoughBuyTokensOnL2(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenBalanceOfComptroller = (1 * exchangePrice) /
            buyTokenPrice;

        // Make sure that L2Comptroller doesn't have enough buy tokens.
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
        vm.expectEmit(true, true, false, false, address(L2ComptrollerProxy));

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            0,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1,
            "Alice's L1 burnt amount incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = ((tokenToBurnAmount1 +
            tokenToBurnAmount2) * exchangePrice) / buyTokenPrice;

        buyTokenBalanceOfComptroller = type(uint256).max;

        // Comptroller now has enough tokens for a claim.
        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(
            alice,
            alice,
            tokenToBurnAmount1 + tokenToBurnAmount2
        );

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );

        // Subtracting from `buyTokenBalanceOfComptroller` as this was the balance before the 2nd buyback transaction.
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNoBuyTokensOnL2(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = 0;
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();

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
        vm.expectEmit(true, true, false, false, address(L2ComptrollerProxy));

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            0,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1,
            "Alice's L1 burnt amount incorrect"
        );

        uint256 expectedBuyTokenAmount = ((tokenToBurnAmount1 +
            tokenToBurnAmount2) * exchangePrice) / buyTokenPrice;

        buyTokenBalanceOfComptroller = type(uint256).max;

        // Comptroller now has enough tokens for a claim.
        deal(
            address(tokenToBuy),
            address(L2ComptrollerProxy),
            buyTokenBalanceOfComptroller
        );

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(
            alice,
            alice,
            tokenToBurnAmount1 + tokenToBurnAmount2
        );

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            tokenToBurnAmount1 + tokenToBurnAmount2,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1_FollowedByOnL2(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 buyTokenPrice = tokenToBuy.tokenPrice();
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

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

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount1 * exchangePrice) /
            buyTokenPrice;

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        changePrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            tokenToBurnAmount2
        );

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount2 * exchangePrice) /
            buyTokenPrice;

        L2ComptrollerProxy.buyBack(alice, tokenToBurnAmount2);

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
