// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "./helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../src/L1Comptroller.sol";
import {L2Comptroller} from "../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBack is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, bytes reason);
    event AssertErrorDuringBuyBack(address indexed depositor, string reason);

    // Custom errors in L2Comptroller and L1Comptroller contracts.
    error OnlyCrossChainAllowed();
    error PriceDropExceedsLimit(
        uint256 minAcceptablePrice,
        uint256 actualPrice
    );

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToBuyback_WhenReceiverIsSender() public {
        uint256 aliceBurnTokenBalanceBefore = tokenToBurnL2.balanceOf(alice);
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(
            burnMultiSig
        );
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(alice, 100e18);
        uint256 expectedBuyTokenAmount = (100e18 * exchangePrice) /
            buyTokenPrice;

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
        assertEq(
            buyTokenAmount,
            expectedBuyTokenAmount,
            "Wrong calculation after buyback"
        );
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
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(
            burnMultiSig
        );
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(
            dummyReceiver,
            100e18
        );
        uint256 expectedBuyTokenAmount = (100e18 * exchangePrice) /
            buyTokenPrice;

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
        assertEq(
            buyTokenAmount,
            expectedBuyTokenAmount,
            "Wrong calculation after buyback"
        );
        assertEq(
            expectedBuyTokenAmount,
            tokenToBuy.balanceOf(dummyReceiver),
            "Wrong buy token amount received"
        );
        assertEq(
            aliceBuyTokenBalanceBefore,
            tokenToBuy.balanceOf(alice),
            "Alice shouldn't have received buy tokens"
        );
    }

    function test_Revert_WhenNotEnoughBurnTokensWithUser() public {
        uint256 aliceBurnTokenBalanceBefore = tokenToBurnL2.balanceOf(alice);

        vm.startPrank(alice);

        // Approve infinite MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            type(uint256).max
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        L2ComptrollerProxy.buyBack(alice, aliceBurnTokenBalanceBefore + 1);

        // Testing if specifying another receiver address doesn't magically enable some transfer to happen.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        L2ComptrollerProxy.buyBack(
            makeAddr("dummyReceiver"),
            aliceBurnTokenBalanceBefore + 1
        );
    }

    function test_Revert_WhenNotEnoughBuyTokensInL2Comptroller() public {
        // Impersonate L2Comptroller and transfer tokenToBuy to some random address for this test.
        vm.startPrank(address(L2ComptrollerProxy));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        changePrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }

    function test_Revert_WhenNoBuyTokensInL2Comptroller() public {
        // Impersonate L2Comptroller and transfer tokenToBuy to some random address for this test.
        vm.startPrank(address(L2ComptrollerProxy));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        changePrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }

    function test_Revert_WhenBuyTokenPriceLow() public {
        uint256 currentTokenPrice = tokenToBuy.tokenPrice();
        uint256 newTokenPrice = currentTokenPrice -
            ((currentTokenPrice * uint256(11)) / uint256(10000)); // 0.11% deviation

        // Mocking the token price call of `tokenToBuy` such that it returns a low price.
        vm.mockCall(
            address(tokenToBuy),
            abi.encodeWithSignature("tokenPrice()"),
            abi.encode(newTokenPrice)
        );

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            100e18
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PriceDropExceedsLimit.selector,
                currentTokenPrice -
                    ((currentTokenPrice *
                        L2ComptrollerProxy.maxTokenPriceDrop()) / 10_000),
                newTokenPrice
            )
        );

        L2ComptrollerProxy.buyBack(alice, 100e18);
    }
}

contract BuyBackFromL1 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, bytes reason);
    event AssertErrorDuringBuyBack(address indexed depositor, string reason);

    // Custom errors in L2Comptroller and L1Comptroller contracts.
    error OnlyCrossChainAllowed();
    error PriceDropExceedsLimit(
        uint256 minAcceptablePrice,
        uint256 actualPrice
    );

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
        // Impersonate L2Comptroller and transfer tokenToBuy to some random address for this test.
        vm.startPrank(address(L2ComptrollerProxy));

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

        changePrank(address(L2DomainMessenger));

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerProxy));

        emit AssertErrorDuringBuyBack(
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
        // Impersonate L2Comptroller and transfer tokenToBuy to some random address for this test.
        vm.startPrank(address(L2ComptrollerProxy));

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

        changePrank(address(L2DomainMessenger));

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerProxy));

        emit AssertErrorDuringBuyBack(
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
        vm.expectRevert(OnlyCrossChainAllowed.selector);

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

        vm.expectRevert(OnlyCrossChainAllowed.selector);
        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, bob, 100e18);

        vm.clearMockedCalls();
    }
}
