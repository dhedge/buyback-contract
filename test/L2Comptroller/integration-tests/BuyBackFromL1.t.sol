// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {Encoding} from "../../helpers/Encoding.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1ComptrollerOPV1} from "../../../src/op-stack/v1/L1ComptrollerOPV1.sol";
import {L2ComptrollerOPV1} from "../../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import {ICrossDomainMessenger} from "../../../src/interfaces/ICrossDomainMessenger.sol";

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
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));
        uint256 expectedBuyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1_WhenSenderIsNotReceiver() public {
        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 dummyReceiverBuyTokenBalanceBefore = tokenToBuy.balanceOf(dummyReceiver);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));
        uint256 expectedBuyTokenAmount = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenEnoughBuyTokensOnL2() public {
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));
        uint256 expectedBuyTokenAmount1 = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Since L2ComptrollerProxy checks for the cross chain msg sender during the "buyBackFromL1" function call,
        // we need the L2DomainMessenger to report the correct cross-chain caller.
        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        uint256 expectedBuyTokenAmount2 = (50e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        // Second buy back on L1 burned 50e18 tokens.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, 150e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount1 + expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Buy token balance of Alice incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount1 - expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of L2Comptroller incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 150e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 150e18, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNotEnoughBuyTokensOnL2() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 2e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 2e18);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 0, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L1 burnt amount incorrect");
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = (150e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 150e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 150e18, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1MultipleTimes_WhenNoBuyTokensOnL2() public {
        vm.startPrank(address(L2DomainMessenger));

        // This makes the tokenToBuy balanceOf L2ComptrollerProxy 2e18.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, 100e18);

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 0, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L1 burnt amount incorrect");
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = (150e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 150e18, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 150e18, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function test_ShouldBeAbleToBuyBackFromL1_FollowedByOnL2() public {
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 buyTokenBalanceOfComptroller = tokenToBuy.balanceOf(address(L2ComptrollerProxy));
        uint256 expectedBuyTokenAmount1 = (100e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

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
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), 100e18);

        uint256 expectedBuyTokenAmount2 = (50e18 * L2ComptrollerProxy.exchangePrice()) / tokenToBuy.tokenPrice();

        L2ComptrollerProxy.buyBack(alice, 50e18);

        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount1 + expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(alice),
            "Alice's buy token balance incorrect"
        );
        assertEq(
            buyTokenBalanceOfComptroller - expectedBuyTokenAmount1 - expectedBuyTokenAmount2,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Comptroller's buy token balance incorrect"
        );
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 100e18, "Alice's claim amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 100e18, "Alice's L2 burn amount incorrect");
    }

    function test_TotalAmountClaimed_ShouldAlwaysIncrease() public {
        ICrossDomainMessengerMod l2xdm = ICrossDomainMessengerMod(0x4200000000000000000000000000000000000007);

        // Simulate a situation where L2Comptroller has no funds & is paused.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        address owner = L2ComptrollerProxy.owner();

        // Pausing the L2Comptroller contract.
        vm.prank(owner);
        L2ComptrollerProxy.pause();

        // Send two txs, one for 1e18 totalBurned and one for 2e18 totalBurned.
        address aliasedXDM = AddressAliasHelper.applyL1ToL2Alias(l2xdm.OTHER_MESSENGER());

        uint256 nonce100 = Encoding.encodeVersionedNonce({_nonce: 100, _version: 1});
        uint256 nonce200 = Encoding.encodeVersionedNonce({_nonce: 200, _version: 1});

        vm.startPrank(aliasedXDM);

        l2xdm.relayMessage({
            _nonce: nonce100,
            _sender: address(L1ComptrollerProxy),
            _target: address(L2ComptrollerProxy),
            _value: 0,
            _minGasLimit: 0,
            _message: abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 1e18)
        });

        l2xdm.relayMessage({
            _nonce: nonce200,
            _sender: address(L1ComptrollerProxy),
            _target: address(L2ComptrollerProxy),
            _value: 0,
            _minGasLimit: 0,
            _message: abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 2e18)
        });

        vm.stopPrank();

        // Unpause the L2Comptroller.
        vm.prank(owner);
        L2ComptrollerProxy.unpause();

        // Execute the 2e18 transaction first, and then the 1e18 transaction.
        // In OP Bedrock upgrade, anyone can call this (except the XDM), but on old OP system we need to prank aliased XDM.
        vm.startPrank(admin);

        l2xdm.relayMessage({
            _nonce: nonce200,
            _sender: address(L1ComptrollerProxy),
            _target: address(L2ComptrollerProxy),
            _value: 0,
            _minGasLimit: 0,
            _message: abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 2e18)
        });

        l2xdm.relayMessage({
            _nonce: nonce100,
            _sender: address(L1ComptrollerProxy),
            _target: address(L2ComptrollerProxy),
            _value: 0,
            _minGasLimit: 0,
            _message: abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 1e18)
        });

        vm.stopPrank();

        uint256 buyTokenBalanceOfComptroller = 10e18;

        // Add funds to the contract.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // user calls claimAll
        vm.prank(alice);
        L2ComptrollerProxy.claimAll(alice);

        // The 1e18 totalBurned transaction should have failed since 2e18 totalBurned transaction was replayed first.
        // There will be some rounding error to be taken care of.
        assertApproxEqAbs(
            L2ComptrollerProxy.convertToTokenToBurn(tokenToBuy.balanceOf(alice)),
            2e18,
            100,
            "Incorrect burn token balance of Alice"
        );

        // The L1 burnt amount of Alice should be correct.
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), 2e18, "Incorrect L1 burnt amount of Alice");

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 2e18, "Incorrect Alice's claimed amount");

        // The buy token balance of L2Comptroller should be correct.
        assertApproxEqAbs(
            buyTokenBalanceOfComptroller - L2ComptrollerProxy.convertToTokenToBuy(2e18),
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            100,
            "Incorrect L2Comptroller's buy token balance"
        );
    }

    function test_Revert_WhenCallerIsNotL1Comptroller() public {
        vm.expectRevert(L2ComptrollerOPV1.OnlyCrossChainAllowed.selector);

        // Bob is the attacker here.
        vm.startPrank(bob);

        L2ComptrollerProxy.buyBackFromL1(alice, bob, 100e18);

        vm.clearMockedCalls();
    }

    function test_Revert_WhenCallerIsNotL2DomainMessenger() public {
        // Mocking a call such that the transaction originates from an attacker (Bob)
        // instead of L1Comptroller on L1.
        vm.mockCall(address(L2DomainMessenger), abi.encodeWithSignature("xDomainMessageSender()"), abi.encode(bob));

        vm.expectRevert(L2ComptrollerOPV1.OnlyCrossChainAllowed.selector);
        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, bob, 100e18);

        vm.clearMockedCalls();
    }
}
