import dotenv from "dotenv";
dotenv.config();
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import { HardhatUserConfig } from "hardhat/config";

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
        arbitrum: {
            chainId: 42161,
            url: process.env.ARBITRUM_RPC_URL || "https://arbitrum.llamarpc.com",
            accounts: [process.env.ARBITRUM_PRIVATE_KEY!]
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
};

export default config;
