// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1ComptrollerOPV1} from "../../../src/op-stack/v1/L1ComptrollerOPV1.sol";
import {L2ComptrollerOPV1} from "../../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Claim is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToClaimOnL2_FullClaimAmount_WhenBuyBackFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        uint256 expectedBuyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.claim(alice, 100e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            1000e18 - expectedBuyTokenAmount,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claim amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L2 burn amount incorrect");
    }

    function test_ShouldBeAbleToClaimOnL2_PartialClaimAmount_WhenBuyBackFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        uint256 expectedBuyTokenAmount1 = (70e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.claim(alice, 70e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount1,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            1000e18 - expectedBuyTokenAmount1,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 70e18, "Alice's claim amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L2 burn amount incorrect");

        uint256 expectedBuyTokenAmount2 = (30e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.claim(alice, 30e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount1 + expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            1000e18 - expectedBuyTokenAmount1 - expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claim amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L2 burn amount incorrect");
    }

    function test_Revert_WhenAlreadyClaimedFully() public {
        vm.startPrank(address(L2DomainMessenger));

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceBeforeComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));
        uint256 expectedBuyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            buyTokenBalanceBeforeComptroller - expectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L1 burnt amount incorrect");

        changePrank(alice);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(abi.encodeWithSelector(L2ComptrollerOPV1.ExceedingClaimableAmount.selector, alice, 0, 100e18));

        L2ComptrollerProxy.claim(alice, 100e18);
    }

    function test_Revert_WhenClaimAmountTooHigh_AndBuyBackFromL1Failed() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 0.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(abi.encodeWithSelector(L2ComptrollerOPV1.ExceedingClaimableAmount.selector, alice, 100e18, 150e18));

        L2ComptrollerProxy.claim(alice, 150e18);
    }
}
