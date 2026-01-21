import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
        optimizer: {
            enabled: true,
            runs: 200,
        },
        },
    },
    networks: {
        arbitrumSepolia: {
        url: process.env.ARB_SEPOLIA_RPC || "https://sepolia-rollup.arbitrum.io/rpc",
        accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        chainId: 421614,
        },
    },
    etherscan: {
        apiKey: {
        arbitrumSepolia: process.env.ARBISCAN_API_KEY || "",
        },
        customChains: [
        {
            network: "arbitrumSepolia",
            chainId: 421614,
            urls: {
            apiURL: "https://api-sepolia.arbiscan.io/api",
            browserURL: "https://sepolia.arbiscan.io/",
            },
        },
        ],
    },
};

export default config;