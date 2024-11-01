// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2ComptrollerOPV1} from "../../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Pausable is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAblePauseTheComptroller() public {
        vm.prank(admin);

        L2ComptrollerProxy.pause();

        assertTrue(L2ComptrollerProxy.paused());
    }

    function test_ShouldBeAbleUnpauseTheComptroller() public {
        vm.startPrank(admin);

        L2ComptrollerProxy.pause();

        // Arbitrary skip.
        skip(1 days);

        L2ComptrollerProxy.unpause();

        assertFalse(L2ComptrollerProxy.paused());
    }

    function test_Revert_Pause_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerProxy.pause();
    }

    function test_Revert_Unpause_WhenNotTheOwner() public {
        vm.prank(admin);

        L2ComptrollerProxy.pause();

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerProxy.unpause();
    }
}
