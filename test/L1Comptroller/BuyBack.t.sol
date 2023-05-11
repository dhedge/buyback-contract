// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackOnL2 is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    } 

    function test_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsSender() public {
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
                        "buyBackFromL1(address,address,uint256)",
                        alice,
                        alice,
                        100e18
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.buyBack(alice, 100e18);

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

    function test_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsNotSender() public {
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
                        "buyBackFromL1(address,address,uint256)",
                        alice,
                        dummyReceiver,
                        100e18
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);

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

    function test_ShouldUpdateBurntAmountCorrectly_WhenReceiverIsSender() public {
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        uint256 bobBalanceBefore = tokenToBurnL1.balanceOf(bob);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            200e18
        );

        L1ComptrollerProxy.buyBack(alice, 100e18);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBack(alice, 100e18);

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

        L1ComptrollerProxy.buyBack(alice, 100e18);

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBack(alice, 100e18);

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

    function test_ShouldUpdateBurntAmountCorrectly_WhenReceiverIsNotSender() public {
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

        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);

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

        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);

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
        address dummyReceiver = makeAddr("dummyReceiver");

        // Impersonate the owner of the proxy contract.
        // prank allows for impersonatation only for the next transaction call.
        vm.prank(admin);

        // Pause the L1Comptroller contract (imperosonating admin).
        L1ComptrollerProxy.pause();

        // Expecting revert when buy back is called during paused state.
        vm.expectRevert("Pausable: paused");

        vm.prank(alice);
        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);
    }

    function test_Revert_WhenL2ComptrollerNotSet() public {
        address dummyReceiver = makeAddr("dummyReceiver");

        // Find the slot of the `L2Comptroller` storage variable in the `L1Comptroller` contract.
        uint256 slot = stdstore
            .target(L1ComptrollerImplementation)
            .sig("l2Comptroller()")
            .find();

        // Modify the storage slot to set the `L2Comptroller` variable to address(0).
        vm.store(
            address(L1ComptrollerProxy),
            bytes32(slot),
            bytes32(uint256(0))
        );

        // Impersonate as Alice and call the `buyBack` function.
        // We are expecting this call to revert as L2Comptroller is not set.
        vm.prank(alice);
        vm.expectRevert(L1Comptroller.L2ComptrollerNotSet.selector);

        L1ComptrollerProxy.buyBack(dummyReceiver, 100e18);
    }
}