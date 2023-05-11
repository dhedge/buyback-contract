// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2Comptroller} from "../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract GetClaimableAmount is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed() public {
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

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        uint256 expectedClaimableAmount = (100e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(
            expectedClaimableAmount,
            L2ComptrollerProxy.getClaimableAmount(alice),
            "Alice's claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndPartialClaimDone()
        public
    {
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

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        L2ComptrollerProxy.claim(alice, 70e18);

        uint256 expectedClaimableAmount = (30e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        assertEq(
            expectedClaimableAmount,
            L2ComptrollerProxy.getClaimableAmount(alice),
            "Alice's claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndFullClaimDone()
        public
    {
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

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        L2ComptrollerProxy.claimAll(alice);

        assertEq(
            0,
            L2ComptrollerProxy.getClaimableAmount(alice),
            "Alice's claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndSenderIsNotReceiver()
        public
    {
        address dummyReceiver = makeAddr("dummyReceiver");

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

        emit RequireErrorDuringBuyBack(
            alice,
            "ERC20: transfer amount exceeds balance"
        );

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        changePrank(alice);

        deal(address(tokenToBuy), address(L2ComptrollerProxy), 1000e18);

        L2ComptrollerProxy.claim(dummyReceiver, 70e18);

        uint256 expectedClaimableAmount = (30e18 *
            L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        assertEq(
            expectedClaimableAmount,
            L2ComptrollerProxy.getClaimableAmount(alice),
            "Alice's claimable amount wrong"
        );

        L2ComptrollerProxy.claimAll(dummyReceiver);

        assertEq(
            0,
            L2ComptrollerProxy.getClaimableAmount(alice),
            "Alice's claimable amount wrong"
        );
    }
}
