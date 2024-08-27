// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ICrossDomainMessenger} from "../../../src/interfaces/ICrossDomainMessenger.sol";

import {Encoding} from "../../helpers/Encoding.sol";
import "../../helpers/SetupV2.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

library AddressAliasHelper {
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);

    function applyL1ToL2Alias(address l1Address) internal pure returns (address l2Address) {
        unchecked {
            l2Address = address(uint160(l1Address) + offset);
        }
    }
}

/**
 * @title ICrossDomainMessenger
 * @dev Interface modified and taken from: https://github.com/ethereum-optimism/optimism/blob/e6ef3a900c42c8722e72c2e2314027f85d12ced5/packages/contracts-bedrock/src/universal/CrossDomainMessenger.sol#L87
 */
interface ICrossDomainMessengerMod is ICrossDomainMessenger {
    /// @notice Retrieves the address of the paired CrossDomainMessenger contract on the other chain
    ///         Public getter is legacy and will be removed in the future. Use `otherMessenger()` instead.
    /// @return CrossDomainMessenger contract on the other chain.
    /// @custom:legacy
    function OTHER_MESSENGER() external view returns (address);

    /// @notice Relays a message that was sent by the other CrossDomainMessenger contract. Can only
    ///         be executed via cross-chain call from the other messenger OR if the message was
    ///         already received once and is currently being replayed.
    /// @param _nonce       Nonce of the message being relayed.
    /// @param _sender      Address of the user who sent the message.
    /// @param _target      Address that the message is targeted at.
    /// @param _value       ETH value to send with the message.
    /// @param _minGasLimit Minimum amount of gas that the message can be executed with.
    /// @param _message     Message to send to the target.
    function relayMessage(
        uint256 _nonce,
        address _sender,
        address _target,
        uint256 _value,
        uint256 _minGasLimit,
        bytes calldata _message
    ) external payable;
}

/// @dev Earlier this contract was named `BuyBackFromL1V2` but was renamed to `RedeemFromL1V2` as the keyword `buyBack` has been removed.
contract RedeemFromL1V2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringRedemption(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);

        // Since L2ComptrollerV2Proxy checks for the cross chain msg sender during the "redeemFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerV2Proxy))
        );
    }

    function test_ShouldBeAbleToRedeemFromL1_WhenSenderIsReceiver() public {
        uint256 usdyAliceBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 usdpyAliceBuyTokenBalanceBefore = USDpy.balanceOf(alice);
        uint256 usdyComptrollerBuyTokenBalanceBefore = USDy.balanceOf(address(L2ComptrollerV2Proxy));
        uint256 usdpyComptrollerBuyTokenBalanceBefore = USDpy.balanceOf(address(L2ComptrollerV2Proxy));

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        vm.startPrank(address(L2DomainMessenger));

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

        assertEq(
            usdyAliceBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            usdpyAliceBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            usdyComptrollerBuyTokenBalanceBefore - usdyExpectedBuyTokenAmount,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "L2Comptroller's USDy balance incorrect"
        );
        assertEq(
            usdpyComptrollerBuyTokenBalanceBefore - usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "L2Comptroller's USDpy balance incorrect"
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

    function test_ShouldBeAbleToRedeemFromL1MultipleTimes_WhenEnoughBuyTokensOnL2() public {
        uint256 usdyAliceBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 usdpyAliceBuyTokenBalanceBefore = USDpy.balanceOf(alice);
        uint256 usdyComptrollerBuyTokenBalanceBefore = USDy.balanceOf(address(L2ComptrollerV2Proxy));
        uint256 usdpyComptrollerBuyTokenBalanceBefore = USDpy.balanceOf(address(L2ComptrollerV2Proxy));

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount1 = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount1 = (100e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        vm.startPrank(address(L2DomainMessenger));

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

        uint256 usdyExpectedBuyTokenAmount2 = (50e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount2 = (50e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(
            usdyAliceBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount1 + usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            usdpyAliceBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount1 + usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            usdyComptrollerBuyTokenBalanceBefore - usdyExpectedBuyTokenAmount1 - usdyExpectedBuyTokenAmount2,
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "L2Comptroller's USDy balance incorrect"
        );
        assertEq(
            usdpyComptrollerBuyTokenBalanceBefore - usdpyExpectedBuyTokenAmount1 - usdpyExpectedBuyTokenAmount2,
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "L2Comptroller's USDpy balance incorrect"
        );
        assertEq(aliceTotalUSDyClaimed, 150e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 150e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 150e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 150e18, "Alice's USDpy burnt amount incorrect");
    }

    function test_ShouldBeAbleToRedeemFromL1MultipleTimes_WhenNotEnoughBuyTokensOnL2() public {
        // This makes the buy tokens' balanceOf L2ComptrollerV2Proxy 2e18.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 2e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 2e18);

        uint256 usdyAliceBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 usdpyAliceBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        vm.startPrank(address(L2DomainMessenger));

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 0, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 0, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (150e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (150e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        // Balance of comptroller for buy tokens is now 1000e18.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        (aliceTotalUSDyBurned, aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (aliceTotalUSDpyBurned, aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(
            usdyAliceBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            usdpyAliceBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "USDy token balance of L2Comptroller incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "USDpy token balance of L2Comptroller incorrect"
        );
        assertEq(aliceTotalUSDyClaimed, 150e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 150e18, "Alice's L1 burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 150e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 150e18, "Alice's L1 burnt amount incorrect");
    }

    function test_ShouldBeAbleToRedeemFromL1MultipleTimes_WhenNoBuyTokensOnL2() public {
        // This makes the buy tokens' balanceOf L2ComptrollerV2Proxy 0.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        uint256 usdyAliceBuyTokenBalanceBefore = USDy.balanceOf(alice);
        uint256 usdpyAliceBuyTokenBalanceBefore = USDpy.balanceOf(alice);

        vm.startPrank(address(L2DomainMessenger));

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        // Expecting a revert as there aren't enough tokens in L2Comptroller.
        // Since the try/catch block will handle the error, we are checking for the event emission instead.
        vm.expectEmit(true, true, false, false, address(L2ComptrollerV2Proxy));

        emit RequireErrorDuringRedemption(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 100e18,
            receiver: alice
        });

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 0, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 100e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 0, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 100e18, "Alice's USDpy burnt amount incorrect");

        // We have initiated a buyback for MTA and POTATO_SWAP in return for USDy and USDpy respectively.
        // So calculate the expected buy token amount for USDy and USDpy.
        uint256 usdyExpectedBuyTokenAmount = (150e18 * L2ComptrollerV2Proxy.exchangePrices(address(MTA_L1))) /
            USDy.tokenPrice();
        uint256 usdpyExpectedBuyTokenAmount = (150e18 * L2ComptrollerV2Proxy.exchangePrices(address(POTATO_SWAP))) /
            USDpy.tokenPrice();

        // Balance of comptroller for buy tokens is now 1000e18.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            totalAmountBurntOnL1: 150e18,
            receiver: alice
        });

        (aliceTotalUSDyBurned, aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (aliceTotalUSDpyBurned, aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(
            usdyAliceBuyTokenBalanceBefore + usdyExpectedBuyTokenAmount,
            USDy.balanceOf(alice),
            "Alice's USDy balance incorrect"
        );
        assertEq(
            usdpyAliceBuyTokenBalanceBefore + usdpyExpectedBuyTokenAmount,
            USDpy.balanceOf(alice),
            "Alice's USDpy balance incorrect"
        );
        assertEq(
            1000e18 - usdyExpectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            "USDy token balance of L2Comptroller incorrect"
        );
        assertEq(
            1000e18 - usdpyExpectedBuyTokenAmount, // Subtracting from 1000e18 as this was the balance before the 2nd buyback transaction.
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            "USDpy token balance of L2Comptroller incorrect"
        );
        assertEq(aliceTotalUSDyClaimed, 150e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 150e18, "Alice's L1 burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 150e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 150e18, "Alice's L1 burnt amount incorrect");
    }

    function test_TotalAmountClaimed_ShouldAlwaysIncrease() public {
        ICrossDomainMessengerMod l2xdm = ICrossDomainMessengerMod(0x4200000000000000000000000000000000000007);

        // Simulate a situation where L2Comptroller has no funds & is paused.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 0);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 0);

        address owner = L2ComptrollerV2Proxy.owner();

        // Pausing the L2Comptroller contract.
        vm.startPrank(owner);
        L2ComptrollerV2Proxy.pause();

        // Send 4 txs, 2 for 1e18 totalBurned and 2 for 2e18 totalBurned.
        address aliasedXDM = AddressAliasHelper.applyL1ToL2Alias(l2xdm.OTHER_MESSENGER());
        uint256 nonce101 = Encoding.encodeVersionedNonce({_nonce: 0, _version: 1});
        uint256 nonce102 = Encoding.encodeVersionedNonce({_nonce: 1, _version: 1});
        uint256 nonce201 = Encoding.encodeVersionedNonce({_nonce: 2, _version: 1});
        uint256 nonce202 = Encoding.encodeVersionedNonce({_nonce: 3, _version: 1});

        changePrank(aliasedXDM);

        l2xdm.relayMessage({
            _nonce: nonce101,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(MTA_L1), // tokenBurned
                    address(USDy), // tokenToBuy
                    1e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce102,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(POTATO_SWAP), // tokenBurned
                    address(USDpy), // tokenToBuy
                    1e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce201,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(MTA_L1), // tokenBurned
                    address(USDy), // tokenToBuy
                    2e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce202,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(POTATO_SWAP), // tokenBurned
                    address(USDpy), // tokenToBuy
                    2e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        // Unpause the L2Comptroller.
        changePrank(owner);
        L2ComptrollerV2Proxy.unpause();

        // Execute the 2e18 transaction first, and then the 1e18 transaction.
        // In OP Bedrock upgrade, anyone can call this (except the XDM), but on old OP system we need to prank aliased XDM.
        changePrank(admin);

        l2xdm.relayMessage({
            _nonce: nonce201,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(MTA_L1), // tokenBurned
                    address(USDy), // tokenToBuy
                    2e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce202,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(POTATO_SWAP), // tokenBurned
                    address(USDpy), // tokenToBuy
                    2e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce101,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(MTA_L1), // tokenBurned
                    address(USDy), // tokenToBuy
                    1e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        l2xdm.relayMessage({
            _nonce: nonce102,
            _sender: address(L1ComptrollerV2Proxy),
            _target: address(L2ComptrollerV2Proxy),
            _value: 0,
            _minGasLimit: CROSS_CHAIN_GAS_LIMIT,
            _message: abi.encodeCall(
                L2ComptrollerV2Base.redeemFromL1,
                (
                    address(POTATO_SWAP), // tokenBurned
                    address(USDpy), // tokenToBuy
                    1e18, // totalAmountBurntOnL1
                    alice // receiver
                )
            )
        });

        // Add funds to the contract.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 1000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 1000e18);

        // user calls claimAll
        changePrank(alice);
        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(MTA_L1), tokenToBuy: USDy});
        L2ComptrollerV2Proxy.claimAll({tokenBurned: address(POTATO_SWAP), tokenToBuy: USDpy});

        // The 1e18 totalBurned transaction should have failed since 2e18 totalBurned transaction was replayed first.
        // There will be some rounding error to be taken care of.
        assertApproxEqAbs(
            L2ComptrollerV2Proxy.convertToTokenToBurn(address(MTA_L1), USDy, USDy.balanceOf(alice)),
            2e18,
            100,
            "Incorrect USDy token balance of Alice"
        );
        assertApproxEqAbs(
            L2ComptrollerV2Proxy.convertToTokenToBurn(address(POTATO_SWAP), USDpy, USDpy.balanceOf(alice)),
            2e18,
            100,
            "Incorrect USDpy token balance of Alice"
        );

        (uint256 aliceTotalUSDyBurned, uint256 aliceTotalUSDyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(MTA_L1)
        );
        (uint256 aliceTotalUSDpyBurned, uint256 aliceTotalUSDpyClaimed) = L2ComptrollerV2Proxy.burnAndClaimDetails(
            alice,
            address(POTATO_SWAP)
        );

        assertEq(aliceTotalUSDyClaimed, 2e18, "Alice's USDy claimed amount incorrect");
        assertEq(aliceTotalUSDyBurned, 2e18, "Alice's USDy burnt amount incorrect");
        assertEq(aliceTotalUSDpyClaimed, 2e18, "Alice's USDpy claimed amount incorrect");
        assertEq(aliceTotalUSDpyBurned, 2e18, "Alice's USDpy burnt amount incorrect");

        // As we dealt 1000e18 tokens to the L2Comptroller we use 1000e18.
        assertApproxEqAbs(
            1000e18 - L2ComptrollerV2Proxy.convertToTokenToBuy(address(MTA_L1), USDy, 2e18),
            USDy.balanceOf(address(L2ComptrollerV2Proxy)),
            100,
            "Incorrect L2Comptroller's buy token balance"
        );
        assertApproxEqAbs(
            1000e18 - L2ComptrollerV2Proxy.convertToTokenToBuy(address(POTATO_SWAP), USDpy, 2e18),
            USDpy.balanceOf(address(L2ComptrollerV2Proxy)),
            100,
            "Incorrect L2Comptroller's buy token balance"
        );
    }

    function test_Revert_WhenCallerIsNotL1Comptroller() public {
        vm.expectRevert(L2ComptrollerV2Base.OnlyCrossChainAllowed.selector);

        // Bob is the attacker here.
        vm.startPrank(bob);

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: bob
        });

        vm.clearMockedCalls();
    }

    function test_Revert_WhenCallerIsNotL2DomainMessenger() public {
        // Mocking a call such that the transaction originates from an attacker (Bob)
        // instead of L1Comptroller on L1.
        vm.mockCall(address(L2DomainMessenger), abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(bob));

        vm.expectRevert(L2ComptrollerV2Base.OnlyCrossChainAllowed.selector);
        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerV2Proxy.redeemFromL1({
            tokenBurned: address(MTA_L1),
            tokenToBuy: address(USDy),
            totalAmountBurntOnL1: 100e18,
            receiver: bob
        });

        vm.clearMockedCalls();
    }
}
