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

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 1000e18);

        // Approve the potato swap tokens to the L1Comptroller for burn.
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 1000e18);

        changePrank(bob);

        // Approve the MTA tokens to the L1Comptroller for burn.
        MTA_L1.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 1000e18);

        // Approve the potato swap tokens to the L1Comptroller for burn.
        POTATO_SWAP.safeIncreaseAllowance(address(L1ComptrollerV2Proxy), 1000e18);

        vm.stopPrank();
    }

    function test_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsSender() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);

        vm.startPrank(alice);

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

    function test_ShouldUpdateBurntAmountCorrectly_WhenReceiverIsNotSender() public {
        address dummyReceiver2 = makeAddr("dummyReceiver2");

        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 mtaBobBalanceBefore = MTA_L1.balanceOf(bob);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);
        uint256 potatoSwapBobBalanceBefore = POTATO_SWAP.balanceOf(bob);

        vm.startPrank(alice);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });

        // Initiate the buy back on L1 again.
        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore - 200e18, "Wrong Alice's balance after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 200e18, "Wrong total supply");
        assertEq(POTATO_SWAP.balanceOf(alice), potatoSwapAliceBalanceBefore - 200e18, "Wrong Alice's balance after burn");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 200e18, "Potato swap balance of burn address incorrect");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 200e18, "Burnt MTA amount not updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)), 200e18, "Burnt potato swap amount not updated");

        // Impersonate Bob now.
        changePrank(bob);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver2
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver2
        });

        // Skipping 10 days arbitrarily.
        skip(10 days);

        // Initiate the buy back on L1 again.
        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver2
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver2
        });

        assertEq(MTA_L1.balanceOf(bob), mtaBobBalanceBefore - 200e18, "Wrong Bob's balance after burn");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 400e18, "Wrong total supply");
        assertEq(POTATO_SWAP.balanceOf(bob), potatoSwapBobBalanceBefore - 200e18, "Wrong Bob's balance after burn");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 400e18, "Potato swap balance of burn address incorrect");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(bob, address(MTA_L1)), 200e18, "Burnt MTA amount not updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(bob, address(POTATO_SWAP)), 200e18, "Burnt potato swap amount not updated");
    }

    function test_ShouldBeAbleToBuyBack_WhenZeroBurnAmountGiven() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);
        uint256 burnAddressPotatoSwapBalanceBefore = POTATO_SWAP.balanceOf(BURN_ADDRESS);

        vm.startPrank(alice);

        // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
        // with the relevant data.
        vm.expectCall(
            address(L1DomainMessenger),
            abi.encodeCall(
                L1DomainMessenger.sendMessage,
                (
                    address(L2ComptrollerV2Proxy),
                    abi.encodeCall(
                        L2ComptrollerV2.buyBackFromL1,
                        (address(MTA_L1), address(USDy), 0, alice, alice)
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
                        (address(POTATO_SWAP), address(USDpy), 0, alice, alice)
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 0,
            receiver: alice
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 0,
            receiver: alice
        });

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore, "MTA balance of Alice incorrect after call");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore, "MTA supply wrong after call");
        assertEq(POTATO_SWAP.balanceOf(alice), potatoSwapAliceBalanceBefore, "Potato swap balance of Alice incorrect after call");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 0, "MTA burnt amount should not be updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)), 0, "Potato swap burnt amount should not be updated");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), burnAddressPotatoSwapBalanceBefore, "Potato swap balance of burn address incorrect");
    }

    // When a user calls the function with 0 given as the `burnTokenAmount` after
    // a non-zero value given as `burnTokenAmount`, the call to L2Comptroller should
    // be passed with the correct cumulative burn token amount.
    function test_ShouldPassCorrectCumulativeAmount_WhenZeroAmountGivenAfterNonZeroAmount() public {
        uint256 mtaTokenSupplyBefore = MTA_L1.totalSupply();
        uint256 mtaAliceBalanceBefore = MTA_L1.balanceOf(alice);
        uint256 potatoSwapAliceBalanceBefore = POTATO_SWAP.balanceOf(alice);

        vm.startPrank(alice);

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

        // Expecting a call to be made to the Optimism's cross domain messenger contract on L1
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

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 0,
            receiver: alice
        });

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(POTATO_SWAP),
            tokenToBuy: address(USDpy),
            burnTokenAmount: 0,
            receiver: alice
        });

        assertEq(MTA_L1.balanceOf(alice), mtaAliceBalanceBefore - 100e18, "MTA balance of Alice incorrect after call");
        assertEq(MTA_L1.totalSupply(), mtaTokenSupplyBefore - 100e18, "MTA supply wrong after call");
        assertEq(POTATO_SWAP.balanceOf(alice), potatoSwapAliceBalanceBefore - 100e18, "Potato swap balance of Alice incorrect after call");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(MTA_L1)), 100e18, "MTA burnt amount should be updated");
        assertEq(L1ComptrollerV2Proxy.burntAmountOf(alice, address(POTATO_SWAP)), 100e18, "Potato swap burnt amount should be updated");
        assertEq(POTATO_SWAP.balanceOf(BURN_ADDRESS), 100e18, "Potato swap balance of burn address incorrect");
    }

    function test_Revert_WhenPaused() public {
        // Impersonate the owner of the proxy contract.
        // prank allows for impersonatation only for the next transaction call.
        vm.startPrank(admin);

        // Pause the L1Comptroller contract (imperosonating admin).
        L1ComptrollerV2Proxy.pause();

        // Expecting revert when buy back is called during paused state.
        vm.expectRevert("Pausable: paused");

        changePrank(alice);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });
    }

    function test_Revert_WhenL2ComptrollerNotSet() public {
        // Find the slot of the `L2Comptroller` storage variable in the `L1Comptroller` contract.
        uint256 slot = stdstore.target(L1ComptrollerV2Implementation).sig("l2Comptroller()").find();

        // Modify the storage slot to set the `L2Comptroller` variable to address(0).
        vm.store(address(L1ComptrollerV2Proxy), bytes32(slot), bytes32(uint256(0)));

        // Impersonate as Alice and call the `buyBack` function.
        // We are expecting this call to revert as L2Comptroller is not set.
        vm.startPrank(alice);
        vm.expectRevert(L1ComptrollerV2.L2ComptrollerNotSet.selector);

        L1ComptrollerV2Proxy.buyBack({
            tokenToBurn: address(MTA_L1),
            tokenToBuy: address(USDy),
            burnTokenAmount: 100e18,
            receiver: dummyReceiver
        });
    }
}
