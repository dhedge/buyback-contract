// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {Encoding} from "../../helpers/Encoding.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import {L2Comptroller} from "../../../src/L2Comptroller.sol";
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

contract BuyBackFromL1Fuzz is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    // Events in L2Comptroller and L1Comptroller.
    event RequireErrorDuringBuyBack(address indexed depositor, string reason);

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1_WhenSenderIsReceiver(uint256 tokenToBurnAmount) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount * L2ComptrollerProxy.exchangePrice()) /
            tokenToBuy.tokenPrice();

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), tokenToBurnAmount, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount, "Alice's L1 burnt amount incorrect");

        vm.clearMockedCalls();
    }

    function testFuzz_ShouldBeAbleToBuyBackFromL1_WhenSenderIsNotReceiver(uint256 tokenToBurnAmount) public {
        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        vm.selectFork(l2ForkId);

        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 dummyReceiverBuyTokenBalanceBefore = tokenToBuy.balanceOf(dummyReceiver);
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount * L2ComptrollerProxy.exchangePrice()) /
            tokenToBuy.tokenPrice();

        vm.mockCall(
            address(L2DomainMessenger),
            abi.encodeWithSignature("xDomainMessageSender()"),
            abi.encode(address(L1ComptrollerProxy))
        );

        vm.startPrank(address(L2DomainMessenger));

        L2ComptrollerProxy.buyBackFromL1(alice, dummyReceiver, tokenToBurnAmount);

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), tokenToBurnAmount, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount, "Alice's L1 burnt amount incorrect");

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
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(tokenToBurnAmount1, 1 + buyTokenPrice / exchangePrice, tokenSupplyBefore);

        // Make sure the fuzzer gives amount less than the token supply in case of `tokenToBurn` being the L2 version.
        tokenToBurnAmount2 = bound(tokenToBurnAmount2, 1 + buyTokenPrice / exchangePrice, tokenToBurnL2.totalSupply());

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount1 * exchangePrice) / buyTokenPrice;

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

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount2 * exchangePrice) / buyTokenPrice;

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1 + tokenToBurnAmount2);

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
        uint256 buyTokenBalanceOfComptroller = (1 * exchangePrice) / buyTokenPrice;

        // Make sure that L2Comptroller doesn't have enough buy tokens.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(tokenToBurnAmount1, 1 + buyTokenPrice / exchangePrice, tokenSupplyBefore);

        // Make sure the fuzzer gives amount less than the token supply in case of `tokenToBurn` being the L2 version.
        tokenToBurnAmount2 = bound(tokenToBurnAmount2, 1 + buyTokenPrice / exchangePrice, tokenToBurnL2.totalSupply());

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 0, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount1, "Alice's L1 burnt amount incorrect");
        assertEq(
            buyTokenBalanceOfComptroller,
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Buy token balance of comptroller changed after failed claim"
        );

        uint256 expectedBuyTokenAmount = ((tokenToBurnAmount1 + tokenToBurnAmount2) * exchangePrice) / buyTokenPrice;

        buyTokenBalanceOfComptroller = type(uint256).max;

        // Comptroller now has enough tokens for a claim.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1 + tokenToBurnAmount2);

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
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(tokenToBurnAmount1, 1 + buyTokenPrice / exchangePrice, tokenSupplyBefore);

        // Make sure the fuzzer gives amount less than the token supply in case of `tokenToBurn` being the L2 version.
        tokenToBurnAmount2 = bound(tokenToBurnAmount2, 1 + buyTokenPrice / exchangePrice, tokenToBurnL2.totalSupply());

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

        emit RequireErrorDuringBuyBack(alice, "ERC20: transfer amount exceeds balance");

        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1);

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), 0, "Alice's claimed amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount1, "Alice's L1 burnt amount incorrect");

        uint256 expectedBuyTokenAmount = ((tokenToBurnAmount1 + tokenToBurnAmount2) * exchangePrice) / buyTokenPrice;

        buyTokenBalanceOfComptroller = type(uint256).max;

        // Comptroller now has enough tokens for a claim.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // Second buy back on L1.
        L2ComptrollerProxy.buyBackFromL1(alice, alice, tokenToBurnAmount1 + tokenToBurnAmount2);

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
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        tokenToBurnAmount1 = bound(tokenToBurnAmount1, 1 + buyTokenPrice / exchangePrice, tokenSupplyBefore);

        // Make sure the fuzzer gives amount less than the token supply in case of `tokenToBurn` being the L2 version.
        tokenToBurnAmount2 = bound(tokenToBurnAmount2, 1 + buyTokenPrice / exchangePrice, tokenToBurnL2.totalSupply());

        deal(address(tokenToBurnL2), alice, tokenToBurnAmount2);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 expectedBuyTokenAmount1 = (tokenToBurnAmount1 * exchangePrice) / buyTokenPrice;

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
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(address(L2ComptrollerProxy), tokenToBurnAmount2);

        uint256 expectedBuyTokenAmount2 = (tokenToBurnAmount2 * exchangePrice) / buyTokenPrice;

        L2ComptrollerProxy.buyBack(alice, tokenToBurnAmount2);

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
        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), tokenToBurnAmount1, "Alice's claim amount incorrect");
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount1, "Alice's L2 burn amount incorrect");
    }

    function testFuzz_TotalAmountClaimed_ShouldAlwaysIncrease(
        uint256 tokenToBurnAmount1,
        uint256 tokenToBurnAmount2
    ) public {
        ICrossDomainMessengerMod l2xdm = ICrossDomainMessengerMod(0x4200000000000000000000000000000000000007);

        vm.selectFork(l1ForkId);

        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        vm.selectFork(l2ForkId);

        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();

        tokenToBurnAmount2 = bound(tokenToBurnAmount2, 1 + tokenToBuy.tokenPrice() / exchangePrice, tokenSupplyBefore);

        // As the fuzzer can give values which can yield buy token amount == 0, we don't want the test to revert in such cases.
        // Hence the minimum is also bounded such that at least 1 `tokenToBuy` worth of `tokenToBurn` is used.
        // Also we want tokenToBurnAmount1 to be lesser than tokenToBurnAmount2
        tokenToBurnAmount1 = bound(tokenToBurnAmount1, 1 + tokenToBuy.tokenPrice() / exchangePrice, tokenToBurnAmount2);

        // Simulate a situation where L2Comptroller has no funds & is paused.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 0);

        // Pausing the L2Comptroller contract.
        vm.prank(L2ComptrollerProxy.owner());
        L2ComptrollerProxy.pause();

        // Send two txs, one for 1e18 totalBurned and one for 2e18 totalBurned.
        uint nonce100 = Encoding.encodeVersionedNonce({_nonce: 100, _version: 1});
        uint nonce200 = Encoding.encodeVersionedNonce({_nonce: 200, _version: 1});

        vm.startPrank(AddressAliasHelper.applyL1ToL2Alias(l2xdm.OTHER_MESSENGER()));

        {
            l2xdm.relayMessage({
                _nonce: nonce100,
                _sender: address(L1ComptrollerProxy),
                _target: address(L2ComptrollerProxy),
                _value: 0,
                _minGasLimit: 0,
                _message: abi.encodeWithSignature(
                    "buyBackFromL1(address,address,uint256)",
                    alice,
                    alice,
                    tokenToBurnAmount1
                )
            });

            l2xdm.relayMessage({
                _nonce: nonce200,
                _sender: address(L1ComptrollerProxy),
                _target: address(L2ComptrollerProxy),
                _value: 0,
                _minGasLimit: 0,
                _message: abi.encodeWithSignature(
                    "buyBackFromL1(address,address,uint256)",
                    alice,
                    alice,
                    tokenToBurnAmount2
                )
            });
        }

        vm.stopPrank();

        // Unpause the L2Comptroller.
        vm.prank(L2ComptrollerProxy.owner());
        L2ComptrollerProxy.unpause();

        // Execute the 2e18 transaction first, and then the 1e18 transaction.
        // In OP Bedrock upgrade, anyone can call this (except the XDM), but on old OP system we need to prank aliased XDM.
        vm.startPrank(admin);

        {
            l2xdm.relayMessage({
                _nonce: nonce200,
                _sender: address(L1ComptrollerProxy),
                _target: address(L2ComptrollerProxy),
                _value: 0,
                _minGasLimit: 0,
                _message: abi.encodeWithSignature(
                    "buyBackFromL1(address,address,uint256)",
                    alice,
                    alice,
                    tokenToBurnAmount2
                )
            });

            l2xdm.relayMessage({
                _nonce: nonce100,
                _sender: address(L1ComptrollerProxy),
                _target: address(L2ComptrollerProxy),
                _value: 0,
                _minGasLimit: 0,
                _message: abi.encodeWithSignature(
                    "buyBackFromL1(address,address,uint256)",
                    alice,
                    alice,
                    tokenToBurnAmount1
                )
            });
        }

        vm.stopPrank();

        uint256 buyTokenBalanceOfComptroller = type(uint256).max;

        // Add funds to the contract.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), buyTokenBalanceOfComptroller);

        // user calls claimAll
        vm.prank(alice);
        L2ComptrollerProxy.claimAll(alice);

        // The 1e18 totalBurned transaction should have failed since 2e18 totalBurned transaction was replayed first.
        // There will be some rounding error to be taken care of.
        assertApproxEqAbs(
            L2ComptrollerProxy.convertToTokenToBurn(tokenToBuy.balanceOf(alice)),
            tokenToBurnAmount2,
            10e6,
            "Incorrect burn token balance of Alice"
        );

        // The L1 burnt amount of Alice should be correct.
        assertEq(L2ComptrollerProxy.l1BurntAmountOf(alice), tokenToBurnAmount2, "Incorrect L1 burnt amount of Alice");

        assertEq(L2ComptrollerProxy.claimedAmountOf(alice), tokenToBurnAmount2, "Incorrect Alice's claimed amount");

        // The buy token balance of L2Comptroller should be correct.
        assertEq(
            buyTokenBalanceOfComptroller - (tokenToBurnAmount2 * exchangePrice) / tokenToBuy.tokenPrice(),
            tokenToBuy.balanceOf(address(L2ComptrollerProxy)),
            "Incorrect L2Comptroller's buy token balance"
        );
    }
}
