// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SetL1ComptrollerV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    } 

    function test_ShouldBeAbleToSetL1Comptroller() public {
        // We are creating a dummy L1Comptroller address.
        // The function should work for any address other than address(0).
        address newL1Comptroller = makeAddr("L1Comptroller");

        vm.prank(admin);

        L2ComptrollerV2Proxy.setL1Comptroller(newL1Comptroller);

        assertEq(L2ComptrollerV2Proxy.l1Comptroller(), newL1Comptroller);
    }

    function test_Revert_WhenNotTheOwner() public {
        address newL1Comptroller = makeAddr("L1Comptroller");

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerV2Proxy.setL1Comptroller(newL1Comptroller);
    }

    function test_Revert_WhenNullAddressPassed() public {
        vm.prank(admin);

        vm.expectRevert(L2ComptrollerV2.ZeroAddress.selector);

        L2ComptrollerV2Proxy.setL1Comptroller(address(0));
    }
}