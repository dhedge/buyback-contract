import dotenv from "dotenv";
dotenv.config();
import "hardhat-preprocessor";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import "@openzeppelin/hardhat-defender";
import { HardhatUserConfig } from "hardhat/config";

import "./deployment-scripts/deploy/v2/DeployArbL1Comptroller";
import "./deployment-scripts/deploy/v2/DeployArbL2Comptroller";
import "./deployment-scripts/tasks/L1Handover";
import "./deployment-scripts/tasks/L2Handover";
import "./deployment-scripts/tasks/CheckL1Comptroller";
import "./deployment-scripts/tasks/CheckL2Comptroller";
import "./deployment-scripts/tasks/L1Upgrade";
import "./deployment-scripts/tasks/L2Upgrade";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.18",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        localhost: {
            chainId: 31337,
            url: "http://127.0.0.1:8545",
            timeout: 0,
            accounts: [`0x${process.env.OPTIMISM_PRIVATE_KEY}`]
        },
        optimism: {
            chainId: 10,
            url:
                process.env.OPTIMISM_RPC_URL ||
                "https://opt-mainnet.g.alchemy.com/v2/",
            accounts: [process.env.OPTIMISM_PRIVATE_KEY!]
        },
        ethereum: {
            chainId: 1,
            url:
                process.env.ETHEREUM_RPC_URL ||
                "https://eth.llamarpc.com",
            accounts: [process.env.ETHEREUM_PRIVATE_KEY!]
        },
        arbitrumOne:{
            chainId: 42161,
            url: process.env.ARBITRUM_RPC_URL || "https://arbitrum.llamarpc.com",
            accounts: [process.env.ARBITRUM_PRIVATE_KEY!]
        },
        sepolia: {
            chainId: 11155111,
            url: process.env.ETHEREUM_SEPOLIA_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com",
            accounts: [process.env.TESTNET_PRIVATE_KEY!],
        },
        arbitrumSepolia: {
            chainId: 421614,
            url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc",
            accounts: [process.env.TESTNET_PRIVATE_KEY!],
        }
    },
    etherscan: {
        // https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html#multiple-api-keys-and-alternative-block-explorers
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY!,
            arbitrumOne: process.env.ARBISCAN_API_KEY!,
            sepolia: process.env.ETHERSCAN_API_KEY!,
            optimisticEthereum: process.env.OPTIMISTIC_ETHERSCAN_API_KEY!,
            arbitrumSepolia: process.env.ARBISCAN_API_KEY!
        },
        customChains: [
            {
                network: "arbitrumSepolia",
                chainId: 421614,
                urls: {
                    apiURL: "https://api-sepolia.arbiscan.io/api",
                    browserURL: "https://sepolia.arbiscan.io/",
                }
            }
        ]
    },
    defender: {
        apiKey: process.env.DEFENDER_API_KEY!,
        apiSecret: process.env.DEFENDER_SECRET_KEY!
    }
};

export default config;
