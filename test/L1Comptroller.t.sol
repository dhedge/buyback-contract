// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "./helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

// TODO: Decide on the test naming convention after reading the best practices in Foundry docs.
contract L1ComptrollerTest is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function test_buyBackOnL1_should_burn_token() public {
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

    function test_buyBackOnL1_should_update_burntAmount_correctly() public {
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
}
