import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const AOM3VaultModuleDemo = buildModule("AOM3VaultModuleDemo", (m) => {
    const usdcAddress = m.getParameter("usdcAddress", "0x1baAbB04529D43a73232B713C0FE471f7c7334d5");
    const bridgeAddress = m.getParameter("bridgeAddress", "0x08cfc1B6b2dCF36A1480b99353A354AA8AC56f89");
    const ranking = m.contract("AOM3Ranking");
    const vault = m.contract("AOM3VaultDemo", [ranking, usdcAddress, bridgeAddress]);
    const distributor = m.contract("AOM3RewardDistributorDemo", [usdcAddress, vault]);
    m.call(ranking, "setVault", [vault]);
    m.call(vault, "setRewardDistributor", [distributor]);
    return { vault, distributor, ranking };
});

export default AOM3VaultModuleDemo;