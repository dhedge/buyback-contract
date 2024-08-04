// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/interfaces/IERC20Upgradeable.sol";
import {IERC20Burnable} from "../../src/interfaces/IERC20Burnable.sol";
import {IPoolLogic} from "../../src/interfaces/IPoolLogic.sol";
import {ICrossDomainMessenger} from "../../src/interfaces/ICrossDomainMessenger.sol";
import {IL2CrossDomainMessenger} from "../../src/interfaces/IL2CrossDomainMessenger.sol";

import "../../src/op-stack/v2/L1ComptrollerOPV2.sol";
import "../../src/op-stack/v2/L2ComptrollerOPV2.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

abstract contract SetupV2 is Test {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal admin = makeAddr("admin");
    address internal dummyReceiver = makeAddr("dummyReceiver");
    address internal burnMultiSig = makeAddr("burnMultiSig");
    address[] internal accounts = [admin, alice, bob, burnMultiSig];

    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Cross domain messenger on L1 Ethereum
    ICrossDomainMessenger internal constant L1DomainMessenger =
        ICrossDomainMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);

    // Cross domain messenger on L2 Optimism
    IL2CrossDomainMessenger internal constant L2DomainMessenger =
        IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);

    // Address of the MTA token on Ethereum. This is a IERC20Burnable token.
    IERC20Upgradeable internal constant MTA_L1 = IERC20Burnable(0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2);

    // Address of the dHEDGE Stablecoin Yield pool on Optimsim.
    IPoolLogic internal constant USDy = IPoolLogic(0x0F6eAe52ae1f94Bc759ed72B201A2fDb14891485);

    // Addres of the perpetual delta neutral yield pool on Optimism.
    IPoolLogic internal constant USDpy = IPoolLogic(0xB9243C495117343981EC9f8AA2ABfFEe54396Fc0);

    IERC20Upgradeable internal POTATO_SWAP = IERC20Upgradeable(0x907FeB27f8cc5b003Db7e62dfc2f9B01ce3FADd6);

    uint32 internal constant CROSS_CHAIN_GAS_LIMIT = 1_920_000;

    L1ComptrollerOPV2 internal L1ComptrollerV2Proxy;
    L2ComptrollerOPV2 internal L2ComptrollerV2Proxy;
    address internal L1ComptrollerV2Implementation;
    address internal L2ComptrollerV2Implementation;
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
        proxyAdmin = Create2Upgradeable.deploy(0, SALT, type(ProxyAdmin).creationCode);

        // Create a new L1Comptroller implementation.
        L1ComptrollerV2Implementation = address(new L1ComptrollerOPV2());

        // Create a new L1Comptroller proxy.
        L1ComptrollerV2Proxy = L1ComptrollerOPV2(
            address(
                new TransparentUpgradeableProxy(
                    L1ComptrollerV2Implementation,
                    proxyAdmin,
                    abi.encodeCall(L1ComptrollerOPV2.initialize, (admin, L1DomainMessenger, CROSS_CHAIN_GAS_LIMIT))
                )
            )
        );

        address[] memory burnTokens = new address[](2);
        burnTokens[0] = address(MTA_L1);
        burnTokens[1] = address(POTATO_SWAP);

        // Set burn tokens in the L1Comptroller contract.
        L1ComptrollerV2Proxy.addBurnTokens(burnTokens);

        // Fill the accounts with tokens on Ethereum.
        _fillWallets(address(MTA_L1));
        _fillWallets(address(POTATO_SWAP));

        vm.selectFork(l2ForkId);

        // Deploy the proxyAdmin at the same address as on L1.
        Create2Upgradeable.deploy(0, SALT, type(ProxyAdmin).creationCode);

        // Create a new L2Comptroller implementation.
        L2ComptrollerV2Implementation = address(new L2ComptrollerOPV2());

        // Create a new L2Comptroller proxy.
        L2ComptrollerV2Proxy = L2ComptrollerOPV2(
            address(
                new TransparentUpgradeableProxy(
                    L2ComptrollerV2Implementation,
                    proxyAdmin,
                    abi.encodeCall(L2ComptrollerOPV2.initialize, (admin, L2DomainMessenger))
                )
            )
        );

        // Set the L1Comptroller address in the L2Comptroller contract.
        L2ComptrollerV2Proxy.setL1Comptroller(address(L1ComptrollerV2Proxy));

        // Set the exchange prices of the burn tokens.
        L2ComptrollerV2Proxy.setExchangePrices(
            L2ComptrollerV2Base.BurnTokenSettings({tokenToBurn: address(MTA_L1), exchangePrice: 0.03e18})
        );

        L2ComptrollerV2Proxy.setExchangePrices(
            L2ComptrollerV2Base.BurnTokenSettings({tokenToBurn: address(POTATO_SWAP), exchangePrice: 1e18})
        );

        L2ComptrollerV2Base.BuyTokenSettings[] memory buyTokens = new L2ComptrollerV2Base.BuyTokenSettings[](2);
        buyTokens[0] = L2ComptrollerV2Base.BuyTokenSettings({
            tokenToBuy: USDy,
            maxTokenPriceDrop: 10 // 0.1% max token price drop
        });
        buyTokens[1] = L2ComptrollerV2Base.BuyTokenSettings({
            tokenToBuy: USDpy,
            maxTokenPriceDrop: 1000 // 10% max token price drop
        });

        // Set max token price drops for the buy tokens.
        L2ComptrollerV2Proxy.addBuyTokens(buyTokens);

        // Loading the BuyBack contract with dHEDGE pool tokens.
        deal(address(USDy), address(L2ComptrollerV2Proxy), 100_000e18);
        deal(address(USDpy), address(L2ComptrollerV2Proxy), 100_000e18);

        vm.selectFork(l1ForkId);

        // Set the L2Comptroller address in the L1Comptroller address.
        L1ComptrollerV2Proxy.setL2Comptroller(address(L2ComptrollerV2Proxy));

        vm.stopPrank();
    }

    function _fillWallets(address token) internal {
        // Fill wallets of the dummy addresses
        for (uint i = 0; i < accounts.length; ++i) {
            deal(address(token), accounts[i], 100_000e18); // Loading account with `tokenToBurn`

            if (accounts[i].balance == 0) deal(accounts[i], 100_000e18); // Loading account with native token.
        }
    }
}
