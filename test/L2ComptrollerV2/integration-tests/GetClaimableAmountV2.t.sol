// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract GetClaimableAmountV2 is SetupV2 {
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

        // This makes the buy tokens' balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        assertEq(
            usdyExpectedBuyTokenAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(MTA_L1), USDy, alice),
            "Alice's USDy claimable amount wrong"
        );
        assertEq(
            usdpyExpectedBuyTokenAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(POTATO_SWAP), USDpy, alice),
            "Alice's USDpy claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndPartialClaimDone() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the buy tokens' balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        L2ComptrollerV2Proxy.claim({
            tokenBurned: address(MTA_L1),
            tokenToBuy: USDy,
            burnTokenAmount: 70e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.claim({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: USDpy,
            burnTokenAmount: 70e18,
            receiver: alice
        });

        uint256 usdyExpectedClaimableAmount = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedClaimableAmount = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        assertEq(
            usdyExpectedClaimableAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(MTA_L1), USDy, alice),
            "Alice's USDy claimable amount wrong"
        );
        assertEq(
            usdpyExpectedClaimableAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(POTATO_SWAP), USDpy, alice),
            "Alice's USDpy claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndFullClaimDone() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the buy tokens' balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(MTA_L1), tokenToBuy: USDy, receiver: alice});

        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, receiver: alice});

        assertEq(
            0,
            L2ComptrollerV2Proxy.getClaimableAmount(address(MTA_L1), USDy, alice),
            "Alice's USDy claimable amount wrong"
        );
        assertEq(
            0,
            L2ComptrollerV2Proxy.getClaimableAmount(address(POTATO_SWAP), USDpy, alice),
            "Alice's USDpy claimable amount wrong"
        );
    }

    function test_ShouldReturnCorrectAmount_WhenBuyBackFromL1Failed_AndSenderIsNotReceiver() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: dummyReceiver
        });

        L2ComptrollerV2Proxy.buyBackFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            l1Depositor: alice,
            receiver: dummyReceiver
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        L2ComptrollerV2Proxy.claim({
            tokenBurned: address(MTA_L1),
            tokenToBuy: USDy,
            burnTokenAmount: 70e18,
            receiver: dummyReceiver
        });

        L2ComptrollerV2Proxy.claim({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: USDpy,
            burnTokenAmount: 70e18,
            receiver: dummyReceiver
        });

        uint256 usdyExpectedClaimableAmount = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedClaimableAmount = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        assertEq(
            usdyExpectedClaimableAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(MTA_L1), USDy, alice),
            "Alice's USDy claimable amount wrong"
        );
        assertEq(
            usdpyExpectedClaimableAmount,
            L2ComptrollerV2Proxy.getClaimableAmount(address(POTATO_SWAP), USDpy, alice),
            "Alice's USDpy claimable amount wrong"
        );

        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(MTA_L1), tokenToBuy: USDy, receiver: dummyReceiver});

        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, receiver: dummyReceiver});

        assertEq(
            0,
            L2ComptrollerV2Proxy.getClaimableAmount(address(MTA_L1), USDy, alice),
            "Alice's USDy claimable amount wrong"
        );
        assertEq(
            0,
            L2ComptrollerV2Proxy.getClaimableAmount(address(POTATO_SWAP), USDpy, alice),
            "Alice's USDpy claimable amount wrong"
        );
    }
}
