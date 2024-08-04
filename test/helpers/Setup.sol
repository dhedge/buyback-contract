// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {L1ComptrollerOPV1} from "../../src/op-stack/v1/L1ComptrollerOPV1.sol";
import {L2ComptrollerOPV1} from "../../src/op-stack/v1/L2ComptrollerOPV1.sol";
import {IERC20Burnable} from "../../src/interfaces/IERC20Burnable.sol";
import {IPoolLogic} from "../../src/interfaces/IPoolLogic.sol";
import {ICrossDomainMessenger} from "../../src/interfaces/ICrossDomainMessenger.sol";
import {IL2CrossDomainMessenger} from "../../src/interfaces/IL2CrossDomainMessenger.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

abstract contract Setup is Test {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal admin = makeAddr("admin");
    address internal burnMultiSig = makeAddr("burnMultiSig");
    address[] internal accounts = [admin, alice, bob, burnMultiSig];

    // Cross domain messenger on L1 Ethereum
    ICrossDomainMessenger L1DomainMessenger =
        ICrossDomainMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);

    // Cross domain messenger on L2 Optimism
    IL2CrossDomainMessenger L2DomainMessenger =
        IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);

    // Address of the MTA token on Ethereum.
    IERC20Burnable internal constant tokenToBurnL1 =
        IERC20Burnable(0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2);

    // Address of the MTA token on Optimism.
    IERC20Upgradeable internal constant tokenToBurnL2 =
        IERC20Burnable(0x929B939f8524c3Be977af57A4A0aD3fb1E374b50);

    // Address of the dHEDGE Stablecoin Yield pool on Optimsim.
    IPoolLogic internal constant tokenToBuy =
        IPoolLogic(0x0F6eAe52ae1f94Bc759ed72B201A2fDb14891485);

    L1ComptrollerOPV1 internal L1ComptrollerProxy;
    L2ComptrollerOPV1 internal L2ComptrollerProxy;
    address internal L1ComptrollerImplementation;
    address internal L2ComptrollerlImplementation;
    address internal proxyAdmin;

    uint256 internal l1ForkId;
    uint256 internal l2ForkId;
    bytes32 private constant SALT = keccak256(abi.encodePacked(uint16(69)));

    function setUp() public virtual {
        uint256 l1ForkBlockNumber = vm.envUint("ETHEREUM_FORK_BLOCK_NUMBER");
        uint256 l2ForkBlockNumber = vm.envUint("OPTIMISM_FORK_BLOCK_NUMBER");

        l1ForkId = vm.createFork(vm.rpcUrl("ethereum"), l1ForkBlockNumber);
        l2ForkId = vm.createFork(vm.rpcUrl("optimism"), l2ForkBlockNumber);

        // All the deployments should be done by the admin.
        vm.startPrank(admin);

        vm.selectFork(l1ForkId);

        // Deploy proxy admin for comptrollers. We are using CREATE2 for deterministic deployment
        // on both chains.
        proxyAdmin = Create2Upgradeable.deploy(
            0,
            SALT,
            type(ProxyAdmin).creationCode
        );

        // Create a new L1Comptroller implementation.
        L1ComptrollerImplementation = address(new L1ComptrollerOPV1());

        // Create a new L1Comptroller proxy.
        L1ComptrollerProxy = L1ComptrollerOPV1(
            address(
                new TransparentUpgradeableProxy(
                    L1ComptrollerImplementation,
                    proxyAdmin,
                    ""
                )
            )
        );

        // Initialize the comptroller on L1.
        L1ComptrollerProxy.initialize(
            L1DomainMessenger,
            tokenToBurnL1,
            uint32(1_920_000)
        );

        // Fill the accounts with MTA token on Ethereum.
        _fillWallets(address(tokenToBurnL1));

        vm.selectFork(l2ForkId);

        // Deploy the proxyAdmin at the same address as on L1.
        Create2Upgradeable.deploy(0, SALT, type(ProxyAdmin).creationCode);

        // Create a new L2Comptroller implementation.
        L2ComptrollerlImplementation = address(new L2ComptrollerOPV1());

        // Create a new L2Comptroller proxy.
        L2ComptrollerProxy = L2ComptrollerOPV1(
            address(
                new TransparentUpgradeableProxy(
                    L2ComptrollerlImplementation,
                    proxyAdmin,
                    ""
                )
            )
        );

        // Initialize the L2Comptroller contract.
        L2ComptrollerProxy.initialize(
            L2DomainMessenger,
            tokenToBurnL2,
            tokenToBuy,
            burnMultiSig,
            3e16, // $0.03
            10 // 0.1% max token price drop
        );

        // Set the L1Comptroller address in the L2Comptroller contract.
        L2ComptrollerProxy.setL1Comptroller(address(L1ComptrollerProxy));

        _fillWallets(address(tokenToBurnL2));

        // Loading the BuyBack contract with dHEDGE pool tokens.
        deal(address(tokenToBuy), address(L2ComptrollerProxy), 100_000e18);

        vm.selectFork(l1ForkId);

        // Set the L2Comptroller address in the L1Comptroller address.
        L1ComptrollerProxy.setL2Comptroller(address(L2ComptrollerProxy));

        vm.stopPrank();
    }

    function _fillWallets(address token) internal {
        // Fill wallets of the dummy addresses
        for (uint i = 0; i < accounts.length; ++i) {
            deal(address(token), accounts[i], 100_000e18); // Loading account with `tokenToBurn`
            deal(accounts[i], 100_000e18); // Loading account with native token.
        }
    }
}
