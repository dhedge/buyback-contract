// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "./helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../src/L1Comptroller.sol";
// import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackOnL2 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function test_ShouldBurnCorrectAmountOfTokens() public {
        vm.selectFork(l1ForkId);
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            100e18
        );

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

        L1ComptrollerProxy.buyBackOnL2(100e18);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - 100e18,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 100e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            100e18,
            "Burnt amount not updated"
        );
    }

    function test_ShouldUpdateBurntAmountCorrectly() public {
        vm.selectFork(l1ForkId);
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        uint256 bobBalanceBefore = tokenToBurnL1.balanceOf(bob);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBackOnL2(100e18);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - 200e18,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 200e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            200e18,
            "Burnt amount not updated"
        );

        // Impersonate Bob now.
        changePrank(bob);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBackOnL2(100e18);

        assertEq(
            tokenToBurnL1.balanceOf(bob),
            bobBalanceBefore - 200e18,
            "Wrong Bob's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 400e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(bob),
            200e18,
            "Burnt amount not updated"
        );
    }

    function test_Revert_WhenPaused() public {
        vm.selectFork(l1ForkId);

        // Impersonate the owner of the proxy contract.
        // prank allows for impersonatation only for the next transaction call.
        vm.prank(admin);

        // Pause the L1Comptroller contract (imperosonating admin).
        L1ComptrollerProxy.pause();

        // Expecting revert when buy back is called during paused state.
        vm.expectRevert("Pausable: paused");

        vm.prank(alice);
        L1ComptrollerProxy.buyBackOnL2(100e18);
    }

    function test_Revert_WhenL2ComptrollerNotSet() public {
        vm.selectFork(l1ForkId);

        // Find the slot of the `L2Comptroller` storage variable in the `L1Comptroller` contract.
        uint256 slot = stdstore
            .target(L1ComptrollerImplementation)
            .sig("L2Comptroller()")
            .find();

        // Modify the storage slot to set the `L2Comptroller` variable to address(0).
        vm.store(
            address(L1ComptrollerProxy),
            bytes32(slot),
            bytes32(uint256(0))
        );

        // Impersonate as Alice and call the `buyBackOnL2` function.
        // We are expecting this call to revert as L2Comptroller is not set.
        vm.prank(alice);
        vm.expectRevert(L1Comptroller.L2ComptrollerNotSet.selector);

        L1ComptrollerProxy.buyBackOnL2(100e18);
    }
}

contract BuyBackOnL2AndTransfer is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function test_ShouldBurnAndTransferCorrectAmountOfTokens() public {
        vm.selectFork(l1ForkId);
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            100e18
        );

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

        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - 100e18,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 100e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            100e18,
            "Burnt amount not updated"
        );
    }

    function test_ShouldUpdateBurntAmountCorrectly() public {
        vm.selectFork(l1ForkId);
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        uint256 bobBalanceBefore = tokenToBurnL1.balanceOf(bob);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - 200e18,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 200e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            200e18,
            "Burnt amount not updated"
        );

        // Impersonate Bob now.
        changePrank(bob);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);

        assertEq(
            tokenToBurnL1.balanceOf(bob),
            bobBalanceBefore - 200e18,
            "Wrong Bob's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - 400e18,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(bob),
            200e18,
            "Burnt amount not updated"
        );
    }

    function test_Revert_WhenPaused() public {
        vm.selectFork(l1ForkId);
        address dummyReceiver = makeAddr("dummyReceiver");

        // Impersonate the owner of the proxy contract.
        // prank allows for impersonatation only for the next transaction call.
        vm.prank(admin);

        // Pause the L1Comptroller contract (imperosonating admin).
        L1ComptrollerProxy.pause();

        // Expecting revert when buy back is called during paused state.
        vm.expectRevert("Pausable: paused");

        vm.prank(alice);
        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);
    }

    function test_Revert_WhenL2ComptrollerNotSet() public {
        vm.selectFork(l1ForkId);
        address dummyReceiver = makeAddr("dummyReceiver");

        // Find the slot of the `L2Comptroller` storage variable in the `L1Comptroller` contract.
        uint256 slot = stdstore
            .target(L1ComptrollerImplementation)
            .sig("L2Comptroller()")
            .find();

        // Modify the storage slot to set the `L2Comptroller` variable to address(0).
        vm.store(
            address(L1ComptrollerProxy),
            bytes32(slot),
            bytes32(uint256(0))
        );

        // Impersonate as Alice and call the `buyBackOnL2AndTransfer` function.
        // We are expecting this call to revert as L2Comptroller is not set.
        vm.prank(alice);
        vm.expectRevert(L1Comptroller.L2ComptrollerNotSet.selector);

        L1ComptrollerProxy.buyBackOnL2AndTransfer(dummyReceiver, 100e18);
    }
}

contract ClaimOnL2 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function test_ShouldCallTheCrossDomainMessengerOnL1() public {
        vm.selectFork(l1ForkId);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

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
        L1ComptrollerProxy.claimOnL2();
    }

    function test_TotalAmountBeingClaimedIsCorrect() public {
        vm.selectFork(l1ForkId);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

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

        L1ComptrollerProxy.claimOnL2();

        L1ComptrollerProxy.buyBackOnL2(100e18);

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
                        200e18
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.claimOnL2();
    }

    function test_Revert_WhenNoBuyBackInitiated() public {
        vm.selectFork(l1ForkId);

        vm.startPrank(alice);

        // Expecting a revert since no buyback was ever performed.
        vm.expectRevert(L1Comptroller.InvalidClaim.selector);

        L1ComptrollerProxy.claimOnL2();
    }
}

contract ClaimOnL2AndTransfer is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function test_ShouldCallTheCrossDomainMessengerOnL1() public {
        vm.selectFork(l1ForkId);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

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

        // Initiate a claim on L2.
        L1ComptrollerProxy.claimOnL2AndTransfer(dummyReceiver);
    }

    function test_TotalAmountBeingClaimedIsCorrect() public {
        vm.selectFork(l1ForkId);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBackOnL2(100e18);

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

        L1ComptrollerProxy.claimOnL2AndTransfer(dummyReceiver);

        L1ComptrollerProxy.buyBackOnL2(100e18);

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

        L1ComptrollerProxy.claimOnL2AndTransfer(dummyReceiver);
    }

    function test_Revert_WhenNoBuyBackInitiated() public {
        vm.selectFork(l1ForkId);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Expecting a revert since no buyback was ever performed.
        vm.expectRevert(L1Comptroller.InvalidClaim.selector);

        L1ComptrollerProxy.claimOnL2AndTransfer(dummyReceiver);
    }
}
