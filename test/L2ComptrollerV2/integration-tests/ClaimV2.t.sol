// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

/// @dev All tests containing "DifferentBuyToken" in their name check if a user is able to claim/buy a different token than the one they intended to buy
/// when they burnt a token on L1. Example, let's say the buyback request for MTA -> USDy failed (not enough buy tokens on L2), but
/// the user should still be able to claim USDpy instead of USDy in case there is enough USDpy buy tokens on L2.
contract ClaimV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringRedemption(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToClaimOnL2_FullClaimAmount_WhenRedemptionFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        uint256 aliceUSDyBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 aliceUSDpyBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 100e18});

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, burnTokenAmount: 100e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 100e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 100e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");
    }

    /// @dev This test is to check if a user is able to claim/buy a different token than the one they intended to buy
    /// when they burnt a token on L1. Example, let's say the buyback request for MTA -> USDy failed (not enough buy tokens on L2), but
    /// the user can still claim USDpy instead of USDy in case there is enough USDpy buy tokens on L2.
    function test_ShouldBeAbleToClaimOnL2_DifferentBuyToken_FullClaimAmount_WhenRedemptionFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        uint256 aliceUSDyBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 aliceUSDpyBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDpy.tokenPrice();

        // Alice should be able to claim USDpy instead of USDy.
        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDpy, burnTokenAmount: 100e18});

        // Alice should be able to claim USDy instead of USDpy.
        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDy, burnTokenAmount: 100e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 100e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 100e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");
    }

    function test_ShouldBeAbleToClaimOnL2_PartialClaimAmount_WhenRedemptionFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        uint256 aliceUSDyBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 aliceUSDpyBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount1 = (70e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount1 = (70e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 70e18});

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, burnTokenAmount: 70e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount1,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount1,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount1,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount1,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 70e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 70e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount2 = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount2 = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 30e18});

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, burnTokenAmount: 30e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount1 + usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount1 + usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount1 - usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount1 - usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (aliceTotalUSDyBurned, aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (aliceTotalUSDpyBurned, aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 100e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 100e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");
    }

    function test_ShouldBeAbleToClaimOnL2_PartialClaimAmount_DifferentBuyToken_WhenRedemptionFromL1Fails() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        uint256 aliceUSDyBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 aliceUSDpyBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount1 = (70e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount1 = (70e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDpy, burnTokenAmount: 70e18});

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDy, burnTokenAmount: 70e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount1,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount1,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount1,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount1,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 70e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 70e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount2 = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount2 = (30e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDpy.tokenPrice();

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDpy, burnTokenAmount: 30e18});

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDy, burnTokenAmount: 30e18});

        assertEq(
            aliceUSDyBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount1 + usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            aliceUSDpyBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount1 + usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount1 - usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount1 - usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "Comptroller's buy token balance incorrect"
        );

        (aliceTotalUSDyBurned, aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (aliceTotalUSDpyBurned, aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 100e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 100e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");
    }

    function test_Revert_WhenAlreadyClaimedFully() public {
        vm.startPrank(address(L2DomainMessenger));

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(MTA_L1),
                0,
                100e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 100e18});

        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(POTATO_SWAP),
                0,
                100e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, burnTokenAmount: 100e18});
    }

    function test_Revert_DifferentBuyToken_WhenAlreadyClaimedFully() public {
        vm.startPrank(address(L2DomainMessenger));

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(MTA_L1),
                0,
                100e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDpy, burnTokenAmount: 100e18});

        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(POTATO_SWAP),
                0,
                100e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDy, burnTokenAmount: 100e18});
    }

    function test_Revert_WhenClaimAmountTooHigh_AndRedemptionFromL1Failed() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 1000e18.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(MTA_L1),
                100e18,
                150e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 150e18});

        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(POTATO_SWAP),
                100e18,
                150e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy, burnTokenAmount: 150e18});
    }

    function test_Revert_WhenClaimAmountTooHigh_DifferentBuyToken_AndRedemptionFromL1Failed() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, false, false, true, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        changePrank(alice);

        // This makes the tokenToBuy balanceOf L2ComptrollerV2Proxy 1000e18.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // As Alice's cross chain buyback call was successful, she shouldn't be able to claim again.
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(MTA_L1),
                100e18,
                150e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDpy, burnTokenAmount: 150e18});

        vm.expectRevert(
            abi.encodeWithSelector(
                L2ComptrollerV2Base.ExceedingClaimableAmount.selector,
                alice,
                address(POTATO_SWAP),
                100e18,
                150e18
            )
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDy, burnTokenAmount: 150e18});
    }

    function test_Revert_WhenNoTokensBurntOnL1() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(L2ComptrollerV2Base.ExceedingClaimableAmount.selector, alice, address(MTA_L1), 0, 100e18)
        );

        L2ComptrollerV2Proxy.claim({tokenBurned: address(MTA_L1), tokenToBuy: USDy, burnTokenAmount: 100e18});
    }
}
