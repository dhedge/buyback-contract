// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ClaimOnL2 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    }

    function test_ShouldCallTheCrossDomainMessengerOnL1_WhenReceiverIsSender() public {
        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(alice, 100e18);

        // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerProxy),
                    abi.encodeWithSignature(
                        "buyBackFromL1(address,address,uint)",
                        alice,
                        alice,
                        100e18
                    ),
                    1_920_000
                )
            )
        );

        // Initiate a claim on L2.
        L1ComptrollerProxy.claimOnL2(alice);
    }

    function test_TotalAmountBeingClaimedIsCorrect_WhenReceiverIsNotSender() public {
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(dummyReceiver, 100e18);

        // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerProxy),
                    abi.encodeWithSignature(
                        "buyBackFromL1(address,address,uint)",
                        alice,
                        dummyReceiver,
                        100e18
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.claimOnL2(dummyReceiver);

        L1ComptrollerProxy.buyBackOnL2(dummyReceiver, 100e18);

        // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerProxy),
                    abi.encodeWithSignature(
                        "buyBackFromL1(address,address,uint)",
                        alice,
                        dummyReceiver,
                        200e18
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.claimOnL2(dummyReceiver);
    }

    function test_Revert_WhenNoBuyBackInitiated_AndReceiverIsSender() public {

        vm.startPrank(alice);

        // Expecting a revert since no buyback was ever performed.
        vm.expectRevert(L1Comptroller.InvalidClaim.selector);

        L1ComptrollerProxy.claimOnL2(alice);
    }

    function test_Revert_WhenNoBuyBackInitiated_AndReceiverIsNotSender() public {
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Expecting a revert since no buyback was ever performed.
        vm.expectRevert(L1Comptroller.InvalidClaim.selector);

        L1ComptrollerProxy.claimOnL2(dummyReceiver);
    }
}