// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

interface IOwnable {
    function owner() external view returns (address);
}

abstract contract DeployArbComptrollerBase is Script {
    function _logDeployment(string memory label, address proxy) internal view {
        console2.log(string.concat(label, " proxy:"), proxy);
        console2.log("Implementation:", Upgrades.getImplementationAddress(proxy));
        console2.log("ProxyAdmin:", Upgrades.getAdminAddress(proxy));
    }

    function _checkOwnership(string memory label, address proxy, address expectedOwner) internal view {
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        address proxyAdminOwner = IOwnable(proxyAdmin).owner();
        address proxyOwner = IOwnable(proxy).owner();

        console2.log(string.concat(label, " ProxyAdmin owner:"), proxyAdminOwner);
        console2.log(string.concat(label, " owner:"), proxyOwner);

        require(proxyAdminOwner == expectedOwner, "unexpected ProxyAdmin owner");
        require(proxyOwner == expectedOwner, "unexpected proxy owner");
    }
}

/// @notice Deploy with FOUNDRY_PROFILE=deploy and the env vars OWNER, ARB_INBOX, PRIVATE_KEY.
/// @dev Run this script against the L1 RPC.
contract DeployArbL1Comptroller is DeployArbComptrollerBase {
    function run() external returns (address proxy) {
        address owner = vm.envAddress("MAINNET_OWNER");
        address inbox = vm.envAddress("ARB_INBOX");
        address deployer = vm.envAddress("DEPLOYER");

        console2.log("Owner:", owner);
        console2.log("Inbox:", inbox);
        console2.log("Deployer:", deployer);

        vm.startBroadcast();

        proxy = Upgrades.deployTransparentProxy(
            "L1ComptrollerArb.sol:L1ComptrollerArb",
            owner,
            abi.encodeWithSignature("initialize(address,address)", owner, inbox)
        );

        vm.stopBroadcast();

        _logDeployment("L1ComptrollerArb", proxy);
        _checkOwnership("L1ComptrollerArb", proxy, owner);
    }
}

/// @notice Deploy with FOUNDRY_PROFILE=deploy and the env vars OWNER and PRIVATE_KEY.
/// @dev Run this script against the Arbitrum RPC.
contract DeployArbL2Comptroller is DeployArbComptrollerBase {
    function run() external returns (address proxy) {
        address owner = vm.envAddress("ARB_OWNER");
        address deployer = vm.envAddress("DEPLOYER");

        console2.log("Owner:", owner);
        console2.log("Deployer:", deployer);

        vm.startBroadcast();

        // Keep the initial ProxyAdmin owner as the broadcaster to match the current handover flow.
        proxy = Upgrades.deployTransparentProxy(
            "L2ComptrollerArb.sol:L2ComptrollerArb",
            owner,
            abi.encodeWithSignature("initialize(address)", owner)
        );

        vm.stopBroadcast();

        _logDeployment("L2ComptrollerArb", proxy);
        _checkOwnership("L2ComptrollerArb", proxy, owner);
    }
}