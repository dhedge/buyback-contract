// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2Comptroller} from "../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ModifyThreshold is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleModifyThreshold() public {
        vm.prank(admin);

        L2ComptrollerProxy.modifyThreshold(50); // Changing to 0.5%

        assertEq(
            L2ComptrollerProxy.maxTokenPriceDrop(),
            50,
            "Max token pricedrop modification failed"
        );
    }

    function test_Revert_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L2ComptrollerProxy.modifyThreshold(50);
    }
}
