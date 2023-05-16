// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Pausable is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    }

    function test_ShouldBeAblePauseTheComptroller() public {
        vm.prank(admin);

        L1ComptrollerProxy.pause();

        assertTrue(L1ComptrollerProxy.paused());
    }

    function test_ShouldBeAbleUnpauseTheComptroller() public {
        vm.startPrank(admin);

        L1ComptrollerProxy.pause();

        // Arbitrary skip.
        skip(1 days);

        L1ComptrollerProxy.unpause();

        assertFalse(L1ComptrollerProxy.paused());
    }

    function test_Revert_Pause_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L1ComptrollerProxy.pause();
    }

    function test_Revert_Unpause_WhenNotTheOwner() public {
        vm.prank(admin);

        L1ComptrollerProxy.pause();

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L1ComptrollerProxy.unpause();
    }
}
