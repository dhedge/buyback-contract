import dotenv from "dotenv";
dotenv.config();
import fs from "fs";
import "hardhat-preprocessor";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import { HardhatUserConfig, task } from "hardhat/config";

import "./deployment-scripts/tasks/L1Handover.ts";
import "./deployment-scripts/tasks/L2Handover.ts";

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
        },
        optimism: {
            chainId: 10,
            url:
                process.env.OPTIMISM_RPC_URL ||
                "https://opt-mainnet.g.alchemy.com/v2/",
            accounts: process.env.OPTIMISM_PRIVATE_KEY
                ? [process.env.OPTIMISM_PRIVATE_KEY]
                : [],
        },
        ethereum: {
            chainId: 1,
            url:
                process.env.ETHEREUM_RPC_URL ||
                "https://eth-mainnet.g.alchemy.com/v2/",
            accounts: process.env.ETHEREUM_PRIVATE_KEY
                ? [process.env.ETHEREUM_PRIVATE_KEY]
                : [],
        },
    },
    etherscan: {
        // https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html#multiple-api-keys-and-alternative-block-explorers
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY!,
            optimisticEthereum: process.env.OPTIMISTIC_ETHERSCAN_API_KEY!,
        },
    },
};

export default config;
