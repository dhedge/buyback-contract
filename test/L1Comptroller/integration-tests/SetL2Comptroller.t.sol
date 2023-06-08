// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SetL2Comptroller is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    } 

    function test_ShouldBeAbleToSetL2Comptroller() public {
        // We are creating a dummy L2Comptroller address.
        // The function should work for any address other than address(0).
        address newL2Comptroller = makeAddr("L2Comptroller");

        vm.prank(admin);

        L1ComptrollerProxy.setL2Comptroller(newL2Comptroller);

        assertEq(L1ComptrollerProxy.l2Comptroller(), newL2Comptroller);
    }

    function test_Revert_WhenNotTheOwner() public {
        address newL2Comptroller = makeAddr("L2Comptroller");

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L1ComptrollerProxy.setL2Comptroller(newL2Comptroller);
    }

    function test_Revert_WhenNullAddressPassed() public {
        vm.prank(admin);

        vm.expectRevert(L1Comptroller.ZeroAddress.selector);

        L1ComptrollerProxy.setL2Comptroller(address(0));
    }
}