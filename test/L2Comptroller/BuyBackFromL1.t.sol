// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../src/L1Comptroller.sol";
import {L2Comptroller} from "../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackFromL1 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToBuyBackFromL1_WhenSenderIsReceiver() public {
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );
        uint256 expectedBuyTokenAmount = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

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
            100e18,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            100e18,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1_WhenSenderIsNotReceiver() public {
        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 dummyReceiverBuyTokenBalanceBefore = tokenToBuy.balanceOf(
            dummyReceiver
        );
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );
        uint256 expectedBuyTokenAmount = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, dummyReceiver, 100e18);

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
            100e18,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            100e18,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenEnoughBuyTokensOnL2()
        public
    {
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );
        uint256 expectedBuyTokenAmount1 = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        uint256 expectedBuyTokenAmount2 = (50e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, 150e18);

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
            150e18,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            150e18,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNotEnoughBuyTokensOnL2()
        public
    {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 2e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 2e18);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );

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

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            0,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            100e18,
            "Alice's L1 burnt amount incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = (150e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Balance of comptroller for buy token is now 1000e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, 150e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            1000e18 - expectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            150e18,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            150e18,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNoBuyTokensOnL2()
        public
    {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 2e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );

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

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            0,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            100e18,
            "Alice's L1 burnt amount incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = (150e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Balance of comptroller for buy token is now 1000e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, 150e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            1000e18 - expectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(
            L2ComptrollerProxy.claimedAmountOf(alice),
            150e18,
            "Alice's claimed amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            150e18,
            "Alice's L1 burnt amount incorrect"
        );

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1_FollowedByOnL2() public {
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(
            address(L2ComptrollerProxy)
        );
        uint256 expectedBuyTokenAmount1 = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        uint256 expectedBuyTokenAmount2 = (50e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.buyBack(alice, 50e18);

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
            100e18,
            "Alice's claim amount incorrect"
        );
        assertEq(
            L2ComptrollerProxy.l1BurntAmountOf(alice),
            100e18,
            "Alice's L2 burn amount incorrect"
        );
    }

    function test_Revert_WhenCallerIsNotL1Comptroller() public {
        vm.expectRevert(L2Comptroller.OnlyCrossChainAllowed.selector);

        // Bob is the attacker here.
        vm.startPrank(bob);

        L2ComptrollerProxy.buyBackFromL1(alice, bob, 100e18);

        vm.clearMockedCalls();
    }

    function test_Revert_WhenCallerIsNotL2DomainMessenger() public {
        // Mocking a call such that the transaction originates from an attacker (Bob)
        // instead of L1Comptroller on L1.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(bob)
        );

        vm.expectRevert(L2Comptroller.OnlyCrossChainAllowed.selector);
        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, bob, 100e18);

        vm.clearMockedCalls();
    }
}