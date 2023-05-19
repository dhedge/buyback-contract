// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackFuzz is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l1ForkId);
    } 

    function testFuzz_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsSender(uint256 tokenToBurnAmount) public {
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 0, tokenSupplyBefore);

        deal(address(tokenToBurnL1), alice, tokenToBurnAmount);

        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        
        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            tokenToBurnAmount
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
                        "buyBackFromL1(address,address,uint256)",
                        alice,
                        alice,
                        tokenToBurnAmount
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.buyBack(alice, tokenToBurnAmount);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - tokenToBurnAmount,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - tokenToBurnAmount,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            tokenToBurnAmount,
            "Burnt amount not updated"
        );
    }

    function testFuzz_ShouldBurnCorrectAmountOfTokens_WhenReceiverIsNotSender(uint256 tokenToBurnAmount) public {
        uint256 tokenSupplyBefore = tokenToBurnL1.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 0, tokenSupplyBefore);

        deal(address(tokenToBurnL1), alice, tokenToBurnAmount);

        uint256 aliceBalanceBefore = tokenToBurnL1.balanceOf(alice);
        address dummyReceiver = makeAddr("dummyReceiver");

        vm.startPrank(alice);

        // Approve the MTA tokens to the L1Comptroller for burn.
        IERC20Upgradeable(tokenToBurnL1).safeIncreaseAllowance(
            address(L1ComptrollerProxy),
            tokenToBurnAmount
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
                        "buyBackFromL1(address,address,uint256)",
                        alice,
                        dummyReceiver,
                        tokenToBurnAmount
                    ),
                    1_920_000
                )
            )
        );

        L1ComptrollerProxy.buyBack(dummyReceiver, tokenToBurnAmount);

        assertEq(
            tokenToBurnL1.balanceOf(alice),
            aliceBalanceBefore - tokenToBurnAmount,
            "Wrong Alice's balance after burn"
        );
        assertEq(
            tokenToBurnL1.totalSupply(),
            tokenSupplyBefore - tokenToBurnAmount,
            "Wrong total supply"
        );
        assertEq(
            L1ComptrollerProxy.burntAmountOf(alice),
            tokenToBurnAmount,
            "Burnt amount not updated"
        );
    }
}