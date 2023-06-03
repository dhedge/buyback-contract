// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/L1Comptroller.sol";
import "src/L2Comptroller.sol";
import {IERC20Burnable} from "../../../src/interfaces/IERC20Burnable.sol";
import {IPoolLogic} from "../../../src/interfaces/IPoolLogic.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";

library AddressAliasHelper {
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);

    function applyL1ToL2Alias(address l1Address) internal pure returns (address l2Address) {
        unchecked {
            l2Address = address(uint160(l1Address) + offset);
        }
    }
}

interface IMTy is IERC20Upgradeable {
    function totalSupply() external view returns (uint);
}

/**
 * @title ICrossDomainMessenger
 * @dev Interface taken from: https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts/contracts/libraries/bridge/ICrossDomainMessenger.sol
 */
interface ICrossDomainMessengerMod is ICrossDomainMessenger {
    function l1CrossDomainMessenger() external view returns(address);

    /**
     * Relays a cross domain message to a contract.
     * @param _target Target contract address.
     * @param _sender Message sender address.
     * @param _message Message to send to the target.
     * @param _messageNonce Nonce for the provided message.
     */
    function relayMessage(
        address _target,
        address _sender,
        bytes memory _message,
        uint256 _messageNonce
    ) external;
}

contract OutofSyncBrickedFundsTest is Test {
    L2Comptroller l2c = L2Comptroller(0x3509816328cf50Fed7631c2F5C9a18c75cd601F0);
    ICrossDomainMessengerMod l2xdm = ICrossDomainMessengerMod(0x4200000000000000000000000000000000000007);
    IMTy mty = IMTy(0x0F6eAe52ae1f94Bc759ed72B201A2fDb14891485);

    function testOutOfSyncBrickedFunds() public {
        vm.createSelectFork(vm.rpcUrl("optimism"), vm.envUint("OPTIMISM_FORK_BLOCK_NUMBER"));

        // simulate a situation where L2Comptroller has no funds & is paused
        address user = makeAddr("user");
        uint bal = mty.balanceOf(address(l2c));
        vm.prank(address(l2c));
        mty.transfer(address(1), bal);
        address owner = l2c.owner();
        vm.prank(owner);
        l2c.pause();

        // send two txs, one for 1e18 totalBurned and one for 2e18 totalBurned
        address aliasedXDM = AddressAliasHelper.applyL1ToL2Alias(l2xdm.l1CrossDomainMessenger());
        uint nonce100 = uint(keccak256(abi.encode("nonce100")));
        uint nonce200 = uint(keccak256(abi.encode("nonce200")));

        vm.startPrank(aliasedXDM);
        l2xdm.relayMessage(
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L1Comptroller
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L2Comptroller
            abi.encodeWithSignature(
                "buyBackFromL1(address,address,uint256)",
                user,
                user,
                1e18
            ),
            nonce100
        );
        l2xdm.relayMessage(
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L1Comptroller
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L2Comptroller
            abi.encodeWithSignature(
                "buyBackFromL1(address,address,uint256)",
                user,
                user,
                2e18
            ),
            nonce200
        );
        vm.stopPrank();

        // unpause the L2Comp contract
        vm.prank(owner);
        l2c.unpause();

        // execute the 2e18 transaction first, and then the 1e18 transaction
        // in bedrock, anyone can call this, but on old OP system we need to prank aliased XDM
        // these will be saved as unclaimed on contract because there are no funds to pay
        vm.startPrank(aliasedXDM);
        l2xdm.relayMessage(
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L1Comptroller
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L2Comptroller
            abi.encodeWithSignature(
                "buyBackFromL1(address,address,uint256)",
                user,
                user,
                2e18
            ),
            nonce200
        );
        l2xdm.relayMessage(
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L1Comptroller
            0x3509816328cf50Fed7631c2F5C9a18c75cd601F0, // L2Comptroller
            abi.encodeWithSignature(
                "buyBackFromL1(address,address,uint256)",
                user,
                user,
                1e18
            ),
            nonce100
        );
        vm.stopPrank();

        // add funds to the contract
        deal(address(mty), address(l2c), 10e18);

        // user calls claimAll
        vm.prank(user);
        l2c.claimAll(user);

        // even though the user should have 2e18 worth of MTy tokens
        // they actually only have ~1e18 worth
        // their `l1BurntAmountOf` is 1e18 as well
        assertApproxEqAbs(l2c.convertToTokenToBurn(mty.balanceOf(user)), 1e18, 100);
        assertEq(l2c.l1BurntAmountOf(user), 1e18);
    }
}