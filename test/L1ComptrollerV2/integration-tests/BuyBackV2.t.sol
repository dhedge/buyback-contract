// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    }

    function test_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsSender() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 100e18);

        // Approve the potato swap tokens to the L1Comptroller for burn.
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 100e18);

        // Expecting 2 calls to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerV2Proxy),
                    abi.encodeCall(
                        L2ComptrollerV2.buyBackFromL1,
                        (address(MTA_L1), address(USDy), 100e18, alice, alice)
                    ),
                    1_920_000
                )
            )
        );

        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerV2Proxy),
                    abi.encodeCall(
                        L2ComptrollerV2.buyBackFromL1,
                        (address(POTATO_SWAP), address(USDpy), 100e18, alice, alice)
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerV2Proxy.buyBack(address(MTA_L1), address(USDy), 100e18, alice);
        L1ComptrollerV2Proxy.buyBack(address(POTATO_SWAP), address(USDpy), 100e18, alice);

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore - 100e18, "Alice's MTA balance wrong after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 100e18, "MTA total supply incorrect");
        assertEq(
            POTATO_SWAP.balanceOf(alice),
            potatoSwapAliceBalanceBefore - 100e18,
            "Alice's potato swap balance wrong after burn"
        );
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 100e18, "Burnt MTA amount not updated");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 100e18, "Potato swap balance of burn address incorrect");
        assertEq(
            L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)),
            100e18,
            "Burnt potato swap amount not updated"
        );
    }

    function test_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsNotSender() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 100e18);

        // Approve the potato swap tokens to the L1Comptroller for burn.
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 100e18);

        // Expecting 2 calls to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerV2Proxy),
                    abi.encodeCall(
                        L2ComptrollerV2.buyBackFromL1,
                        (address(MTA_L1), address(USDy), 100e18, alice, dummyReceiver)
                    ),
                    1_920_000
                )
            )
        );

        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerV2Proxy),
                    abi.encodeCall(
                        L2ComptrollerV2.buyBackFromL1,
                        (address(POTATO_SWAP), address(USDpy), 100e18, alice, dummyReceiver)
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerV2Proxy.buyBack(address(MTA_L1), address(USDy), 100e18, dummyReceiver);
        L1ComptrollerV2Proxy.buyBack(address(POTATO_SWAP), address(USDpy), 100e18, dummyReceiver);

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore - 100e18, "Alice's MTA balance wrong after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 100e18, "MTA total supply incorrect");
        assertEq(
            POTATO_SWAP.balanceOf(alice),
            potatoSwapAliceBalanceBefore - 100e18,
            "Alice's potato swap balance wrong after burn"
        );
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 100e18, "Burnt MTA amount not updated");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 100e18, "Potato swap balance of burn address incorrect");
        assertEq(
            L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)),
            100e18,
            "Burnt potato swap amount not updated"
        );
    }

    function test_ShouldUpdateBurntAmountCorrectly_WhenReceiverIsSender() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 mtaBobBalanceBefore = MTA_L1.balanceOf(bob);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);
        uint256 potatoSwapBobBalanceBefore = POTATO_SWAP.balanceOf(bob);

        vm.startPrank(alice);

        // Approve the burn tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: alice
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: alice
        });

        // Initiate the buy back on L1 again.
        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: alice
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: alice
        });

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore - 200e18, "Wrong Alice's balance after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 200e18, "Wrong total supply");
        assertEq(POTATO_SWAP.balanceOf(alice), potatoSwapAliceBalanceBefore - 200e18, "Wrong Alice's balance after burn");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 200e18, "Potato swap balance of burn address incorrect");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 200e18, "Burnt MTA amount not updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)), 200e18, "Burnt potato swap amount not updated");

        // Impersonate Bob now.
        changePrank(bob);

        // Approve the MTA tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: bob
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: bob
        });

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: bob
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: bob
        });

        assertEq(MTA_L1.balanceOf(bob), mtaBobBalanceBefore - 200e18, "Wrong Bob's balance after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 400e18, "Wrong total supply");
        assertEq(POTATO_SWAP.balanceOf(bob), potatoSwapBobBalanceBefore - 200e18, "Wrong Bob's balance after burn");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 400e18, "Potato swap balance of burn address incorrect");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(bob, address(MTA_L1)), 200e18, "Burnt MTA amount not updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(bob, address(POTATO_SWAP)), 200e18, "Burnt potato swap amount not updated");
    }

    // function test_ShouldUpdateBurntAmountCorrectly_WhenReceiverIsNotSender() public {
    //     uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
    //     uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
    //     uint256 bobBalanceBefore = tokenToBurnL1.balanceOf(bob);
    //     address dummyReceiver = makeAddr("dummyReceiver");

    //     vm.startPrank(alice);

    //     // Approve the MTA tokens to the L1Comptroller for burn.
    //     IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);

    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);

    //     // Initiate the buy back on L1 again.
    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);

    //     assertEq(tokenToBurnL1.balanceOf(alice), aliceBalanceBefore - 200e18, "Wrong Alice's balance after burn");
    //     assertEq(tokenToBurnL1.totalSupply(), tokenSupplyBefore - 200e18, "Wrong total supply");
    //     assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice), 200e18, "Burnt amount not updated");

    //     // Impersonate Bob now.
    //     changePrank(bob);

    //     // Approve the MTA tokens to the L1Comptroller for burn.
    //     IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 200e18);

    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);

    //     // Skipping 10 days arbitrarily.
    //     skip(10 days);

    //     // Initiate the buy back on L1 again.
    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);

    //     assertEq(tokenToBurnL1.balanceOf(bob), bobBalanceBefore - 200e18, "Wrong Bob's balance after burn");
    //     assertEq(tokenToBurnL1.totalSupply(), tokenSupplyBefore - 400e18, "Wrong total supply");
    //     assertEq(L1ComptrollerV2Proxy.burntAmountOf(bob), 200e18, "Burnt amount not updated");
    // }

    // function test_ShouldBeAbleToBuyBack_WhenZeroBurnAmountGiven() public {
    //     uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
    //     uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);

    //     vm.startPrank(alice);

    //     // Approve the MTA tokens to the L1Comptroller for burn.
    //     IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 100e18);

    //     // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
    //     // with the relevant data.
    //     vm.expectCall(
    //         address(L1DomainMessenger),
    //         abi.encodeCall(
    //             L1DomainMessenger.sendMessage,
    //             (
    //                 address(L2ComptrollerV2Proxy),
    //                 abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 0),
    //                 1_920_000
    //             )
    //         )
    //     );

    //     L1ComptrollerV2Proxy.buyBack(alice, 0);

    //     assertEq(tokenToBurnL1.balanceOf(alice), aliceBalanceBefore, "Wrong Alice's balance after burn");
    //     assertEq(tokenToBurnL1.totalSupply(), tokenSupplyBefore, "Wrong total supply");
    //     assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice), 0, "Burnt amount not updated");
    // }

    // // When a user calls the function with 0 given as the `burnTokenAmount` after
    // // a non-zero value given as `burnTokenAmount`, the call to L2Comptroller should
    // // be passed with the correct cumulative burn token amount.
    // function test_ShouldPassCorrectCumulativeAmount_WhenZeroAmountGivenAfterNonZeroAmount() public {
    //     uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();
    //     uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);

    //     vm.startPrank(alice);

    //     // Approve the MTA tokens to the L1Comptroller for burn.
    //     IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 1000e18);

    //     L1ComptrollerV2Proxy.buyBack(alice, 100e18);

    //     // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
    //     // with the relevant data.
    //     vm.expectCall(
    //         address(L1DomainMessenger),
    //         abi.encodeCall(
    //             L1DomainMessenger.sendMessage,
    //             (
    //                 address(L2ComptrollerV2Proxy),
    //                 abi.encodeWithSignature("buyBackFromL1(address,address,uint256)", alice, alice, 100e18),
    //                 1_920_000
    //             )
    //         )
    //     );

    //     L1ComptrollerV2Proxy.buyBack(alice, 0);

    //     assertEq(tokenToBurnL1.balanceOf(alice), aliceBalanceBefore - 100e18, "Wrong Alice's balance after burn");
    //     assertEq(tokenToBurnL1.totalSupply(), tokenSupplyBefore - 100e18, "Wrong total supply");
    //     assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice), 100e18, "Burnt amount not updated");
    // }

    // function test_Revert_WhenPaused() public {
    //     address dummyReceiver = makeAddr("dummyReceiver");

    //     // Impersonate the owner of the proxy contract.
    //     // prank allows for impersonatation only for the next transaction call.
    //     vm.prank(admin);

    //     // Pause the L1Comptroller contract (imperosonating admin).
    //     L1ComptrollerV2Proxy.pause();

    //     // Expecting revert when buy back is called during paused state.
    //     vm.expectRevert("Pausable: paused");

    //     vm.prank(alice);
    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);
    // }

    // function test_Revert_WhenL2ComptrollerNotSet() public {
    //     address dummyReceiver = makeAddr("dummyReceiver");

    //     // Find the slot of the `L2Comptroller` storage variable in the `L1Comptroller` contract.
    //     uint256 slot = stdstore.target(L1ComptrollerImplementation).sig("l2Comptroller()").find();

    //     // Modify the storage slot to set the `L2Comptroller` variable to address(0).
    //     vm.store(address(L1ComptrollerV2Proxy), bytes32(slot), bytes32(uint256(0)));

    //     // Impersonate as Alice and call the `buyBack` function.
    //     // We are expecting this call to revert as L2Comptroller is not set.
    //     vm.prank(alice);
    //     vm.expectRevert(L1Comptroller.L2ComptrollerNotSet.selector);

    //     L1ComptrollerV2Proxy.buyBack(dummyReceiver, 100e18);
    // }
}
