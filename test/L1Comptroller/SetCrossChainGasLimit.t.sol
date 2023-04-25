// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Setup} from "../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SetCrossChainGasLimit is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    }

    function test_ShouldBeAbleToSetCrossChainGasLimit() public {
        vm.prank(admin);

        L1ComptrollerProxy.setCrossChainGasLimit(500_000);

        // Slot of the storage variable `crossChainGasLimit` can be found out using ```forge inspect L1Comptroller storageLayout```.
        bytes32 slotData = vm.load(address(L1ComptrollerProxy), bytes32(uint256(153)));

        uint32 newCrossChainGasLimit;
        assembly {
            // The offset of `crossChainGasLimit` is 20 as per the inspection result so 20 * 8 == 160 bits is required to be shifted right.
            // Anding with 32 bits of 1's gives us our uint32 value.
            newCrossChainGasLimit := and(shr(160, slotData), 0xffffffff)
        }

        assertEq(newCrossChainGasLimit, 500_000);
    }

    function test_Revert_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L1ComptrollerProxy.setCrossChainGasLimit(500_000);
    }

    function test_Revert_WhenZeroGasLimitPassed() public {
        vm.prank(admin);

        vm.expectRevert(L1Comptroller.ZeroValue.selector);

        L1ComptrollerProxy.setCrossChainGasLimit(0);
    }
}
