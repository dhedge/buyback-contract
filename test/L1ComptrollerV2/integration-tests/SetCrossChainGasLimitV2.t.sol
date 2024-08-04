// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1ComptrollerOPV1} from "../../../src/op-stack/v1/L1ComptrollerOPV1.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SetCrossChainGasLimitV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    }

    function test_ShouldBeAbleToSetCrossChainGasLimit() public {
        vm.prank(admin);

        L1ComptrollerV2Proxy.setCrossChainGasLimit(500_000);

        assertEq(L1ComptrollerV2Proxy.crossChainCallGasLimit(), 500_000);
    }

    function test_Revert_WhenNotTheOwner() public {
        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        L1ComptrollerV2Proxy.setCrossChainGasLimit(500_000);
    }

    function test_Revert_WhenZeroGasLimitPassed() public {
        vm.prank(admin);

        vm.expectRevert(L1ComptrollerV2Base.ZeroValue.selector);

        L1ComptrollerV2Proxy.setCrossChainGasLimit(0);
    }
}
