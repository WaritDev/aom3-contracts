import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const AOM3VaultModule = buildModule("AOM3VaultModule", (m) => {
    const usdcAddress = m.getParameter("usdcAddress", "0x75faf114eafb1bdbe2f0316df893fd58ce46aa4d");
    const strategy = m.contract("AOM3Strategy", [usdcAddress]);
    const vault = m.contract("AOM3Vault", [usdcAddress, strategy]);
    const distributor = m.contract("AOM3RewardDistributor", [usdcAddress, vault]);
    m.call(strategy, "setVault", [vault]);
    m.call(strategy, "setRewardDistributor", [distributor]);
    return { vault, strategy, distributor };
});

export default AOM3VaultModule;