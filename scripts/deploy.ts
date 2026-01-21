import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const usdcAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"; 
    const strategyAddress = "0xYOUR_STRATEGY_WALLET_OR_CONTRACT_ADDRESS";

    const AOM3Vault = await ethers.getContractFactory("AOM3Vault");
    const vault = await AOM3Vault.deploy(usdcAddress, strategyAddress);

    await vault.waitForDeployment();
    const vaultAddress = await vault.getAddress();

    console.log(`AOM3Vault deployed to: ${vaultAddress}`);
    console.log("Deployment complete. Verify on Arbiscan Sepolia.");
    }

    main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});