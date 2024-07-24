// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import "../../helpers/SetupV2.sol";

import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract ModifyThresholdV2 is SetupV2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.selectFork(l2ForkId);
    }

    function test_ShouldBeAbleModifyThreshold() public {
        vm.startPrank(admin);

        L2ComptrollerV2Proxy.modifyThreshold(USDy, 50); // Changing to 0.5%
        L2ComptrollerV2Proxy.modifyThreshold(USDpy, 50); // Changing to 0.5%

        (, uint256 usdyMaxTokenPriceDrop) = L2ComptrollerV2Proxy.buyTokenDetails(USDy);
        (, uint256 usdpyMaxTokenPriceDrop) = L2ComptrollerV2Proxy.buyTokenDetails(USDpy);

        assertEq(usdyMaxTokenPriceDrop, 50, "USDy max token pricedrop modification failed");
        assertEq(usdpyMaxTokenPriceDrop, 50, "USDpy max token pricedrop modification failed");

    }

    function test_Revert_WhenNotTheOwner() public {
        vm.startPrank(alice);

        vm.expectRevert("Ownable: caller is not the owner");
        L2ComptrollerV2Proxy.modifyThreshold(USDy, 50);

        vm.expectRevert("Ownable: caller is not the owner");
        L2ComptrollerV2Proxy.modifyThreshold(USDpy, 50);
    }
}
