// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L2ComptrollerOPV1} from "../../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract EmergencyWithdraw is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleToEmergencyWithdraw_PartialAmounts() public {
        ERC20 pepe = new ERC20("Pepe the memecoin", "PEPE");

        // Set the balance of PEPE tokens of L1Comptroller as 1000e18.
        deal(address(pepe), address(L2ComptrollerProxy), 1000e18);

        vm.prank(admin);

        // Withdraw a partial amount of PEPE tokens.
        L2ComptrollerProxy.emergencyWithdraw(address(pepe), 100e18);

        assertEq(100e18, pepe.balanceOf(admin), "Owner balance incorrect");
        assertEq(900e18, pepe.balanceOf(address(L2ComptrollerProxy)), "Comptroller balance incorrect");
    }

    function test_ShouldBeAbleToEmergencyWithdraw_FullAmount() public {
        ERC20 pepe = new ERC20("Pepe the memecoin", "PEPE");

        // Set the balance of PEPE tokens of L1Comptroller as 1000e18.
        deal(address(pepe), address(L2ComptrollerProxy), 1000e18);

        vm.prank(admin);

        // Withdraw full amount of PEPE tokens.
        L2ComptrollerProxy.emergencyWithdraw(address(pepe), type(uint256).max);

        assertEq(1000e18, pepe.balanceOf(admin), "Owner balance incorrect");
        assertEq(0, pepe.balanceOf(address(L2ComptrollerProxy)), "Comptroller balance incorrect");
    }

    function test_Revert_WhenNotTheOwner() public {
        ERC20 pepe = new ERC20("Pepe the memecoin", "PEPE");

        // Set the balance of PEPE tokens of L1Comptroller as 1000e18.
        deal(address(pepe), address(L2ComptrollerProxy), 1000e18);

        vm.prank(alice);

        vm.expectRevert("Ownable: caller is not the owner");

        // Withdraw a partial amount of PEPE tokens.
        L2ComptrollerProxy.emergencyWithdraw(address(pepe), 100e18);

        vm.expectRevert("Ownable: caller is not the owner");

        // Withdraw full amount of PEPE tokens.
        L2ComptrollerProxy.emergencyWithdraw(address(pepe), type(uint256).max);
    }
}
