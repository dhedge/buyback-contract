// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract PausableV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAblePauseTheComptroller() public {
        vm.prank(admin);

        L2ComptrollerV2Proxy.pause();

        assertTrue(L2ComptrollerV2Proxy.paused());
    }

    function test_ShouldBeAbleUnpauseTheComptroller() public {
        vm.startPrank(admin);

        L2ComptrollerV2Proxy.pause();

        // Arbitrary skip.
        skip(1 days);

        L2ComptrollerV2Proxy.unpause();

        assertFalse(L2ComptrollerV2Proxy.paused());
    }

    function test_Revert_Pause_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerV2Proxy.pause();
    }

    function test_Revert_Unpause_WhenNotTheOwner() public {
        vm.prank(admin);

        L2ComptrollerV2Proxy.pause();

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerV2Proxy.unpause();
    }
}
