// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Setup} from "../../helpers/Setup.sol";
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1Comptroller} from "../../../src/L1Comptroller.sol";
import {L2Comptroller} from "../../../src/L2Comptroller.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BuyBackFuzz is Setup {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function testFuzz_ShouldBeAbleToBuyback_WhenReceiverIsSender(
        uint256 tokenToBurnAmount
    ) public {
        uint256 tokenSupplyBefore = tokenToBurnL2.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        deal(address(tokenToBurnL2), alice, tokenToBurnAmount);

        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(
            burnMultiSig
        );
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            tokenToBurnAmount
        );

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(
            alice,
            tokenToBurnAmount
        );
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount * exchangePrice) /
            buyTokenPrice;

        assertEq(
            tokenToBurnL2.balanceOf(burnMultiSig),
            burnMultiSigBalanceBefore + tokenToBurnAmount,
            "Wrong balance of burn multisig"
        );

        assertEq(
            tokenToBurnL2.balanceOf(alice),
            0,
            "Wrong tokenToBurn balance of Alice"
        );
        assertEq(
            buyTokenAmount,
            expectedBuyTokenAmount,
            "Wrong calculation after buyback"
        );
        assertEq(
            aliceBuyTokenBalanceBefore + expectedBuyTokenAmount,
            tokenToBuy.balanceOf(alice),
            "Wrong buy token amount received"
        );
    }

    function testFuzz_ShouldBeAbleToBuyback_WhenReceiverIsNotSender(
        uint256 tokenToBurnAmount
    ) public {
        uint256 tokenSupplyBefore = tokenToBurnL2.totalSupply();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        deal(address(tokenToBurnL2), alice, tokenToBurnAmount);

        address dummyReceiver = makeAddr("dummyReceiver");
        uint256 aliceBuyTokenBalanceBefore = tokenToBuy.balanceOf(alice);
        uint256 burnMultiSigBalanceBefore = tokenToBurnL2.balanceOf(
            burnMultiSig
        );
        uint256 exchangePrice = L2ComptrollerProxy.exchangePrice();
        uint256 buyTokenPrice = tokenToBuy.tokenPrice();

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            tokenToBurnAmount
        );

        uint256 buyTokenAmount = L2ComptrollerProxy.buyBack(
            dummyReceiver,
            tokenToBurnAmount
        );
        uint256 expectedBuyTokenAmount = (tokenToBurnAmount * exchangePrice) /
            buyTokenPrice;

        assertEq(
            tokenToBurnL2.balanceOf(burnMultiSig),
            burnMultiSigBalanceBefore + tokenToBurnAmount,
            "Wrong balance of burn multisig"
        );

        assertEq(
            tokenToBurnL2.balanceOf(alice),
            0,
            "Wrong tokenToBurn balance of Alice"
        );
        assertEq(
            buyTokenAmount,
            expectedBuyTokenAmount,
            "Wrong calculation after buyback"
        );
        assertEq(
            expectedBuyTokenAmount,
            tokenToBuy.balanceOf(dummyReceiver),
            "Wrong buy token amount received"
        );
        assertEq(
            aliceBuyTokenBalanceBefore,
            tokenToBuy.balanceOf(alice),
            "Alice shouldn't have received buy tokens"
        );
    }

    function testFuzz_ShouldUpdateBuyTokenPriceCorrectly(
        uint256 tokenToBurnAmount,
        uint256 modifiedTokenPrice
    ) public {
        uint256 tokenSupplyBefore = tokenToBurnL2.totalSupply();
        uint256 latestTokenToBuyPrice = L2ComptrollerProxy
            .lastTokenToBuyPrice();

        // Make sure the fuzzer gives amount less than the token supply.
        tokenToBurnAmount = bound(tokenToBurnAmount, 1, tokenSupplyBefore);

        // Make sure that the fuzzer gives an amount which doesn't trigger the PriceDropExceedsLimit error.
        modifiedTokenPrice = bound(
            modifiedTokenPrice,
            latestTokenToBuyPrice - (latestTokenToBuyPrice * L2ComptrollerProxy.maxTokenPriceDrop()) /
                L2ComptrollerProxy.DENOMINATOR(),
            type(uint256).max
        );

        deal(address(tokenToBurnL2), alice, tokenToBurnAmount);

        vm.mockCall(
            address(tokenToBuy),
            abi.encodeWithSignature("tokenPrice()"),
            abi.encode(modifiedTokenPrice)
        );

        assertEq(
            tokenToBuy.tokenPrice(),
            modifiedTokenPrice,
            "Token price not modified"
        );

        vm.startPrank(alice);

        // Approve the MTA tokens to the L2Comptroller for buyback.
        IERC20Upgradeable(tokenToBurnL2).safeIncreaseAllowance(
            address(L2ComptrollerProxy),
            tokenToBurnAmount
        );

        L2ComptrollerProxy.buyBack(alice, tokenToBurnAmount);

        if (latestTokenToBuyPrice < modifiedTokenPrice) {
            assertEq(
                L2ComptrollerProxy.lastTokenToBuyPrice(),
                modifiedTokenPrice,
                "Latest buy token price changed"
            );
        }
    }
}
