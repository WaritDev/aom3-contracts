import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { parseUnits } from "viem";

describe("AOM3Vault", function () {
  async function deployVaultFixture() {
    const [owner, user] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const mockUsdc = await hre.viem.deployContract("MockUSDC");
    await mockUsdc.write.mint([user.account.address, parseUnits("1000", 6)]);
    const strategyAddress = "0x6ae43d5349463ad9d7b22e9786232484ad660450";
    const vault = await hre.viem.deployContract("AOM3Vault", [mockUsdc.address, strategyAddress]);
    await mockUsdc.write.approve([vault.address, parseUnits("1000", 6)], { account: user.account });
    
    return { vault, mockUsdc, owner, user, publicClient };
  }

  describe("Quest & Deposit Logic", function () {
    const SECONDS_IN_DAY = 86400n;
    const CYCLE_DAYS = 31n;
    const cycleDuration = SECONDS_IN_DAY * CYCLE_DAYS;

    it("ควรเพิ่ม Streak เมื่อฝากเงินภายใน Window 7 วันแรก", async function () {
      const { vault, user } = await loadFixture(deployVaultFixture);
      const amount = parseUnits("100", 6);

      await vault.write.createQuest([amount, 12n], { account: user.account });

      const currentTimestamp = BigInt(Math.floor(Date.now() / 1000));
      const nextCycleStart = (currentTimestamp / cycleDuration + 1n) * cycleDuration;
      
      await time.setNextBlockTimestamp(nextCycleStart); 

      await vault.write.deposit([0n], { account: user.account });

      const quest = await vault.read.quests([0n]);
      expect(quest[3]).to.equal(1n);
    });

    it("ควร Reset Streak หากฝากเงินนอกช่วง Window", async function () {
      const { vault, user } = await loadFixture(deployVaultFixture);
      const amount = parseUnits("100", 6);
      await vault.write.createQuest([amount, 12n], { account: user.account });

      const currentTimestamp = BigInt(Math.floor(Date.now() / 1000));
      const nextCycleStart = (currentTimestamp / cycleDuration + 1n) * cycleDuration;
      const dayTen = nextCycleStart + (10n * SECONDS_IN_DAY);
      
      await time.setNextBlockTimestamp(dayTen);

      await vault.write.deposit([0n], { account: user.account });

      const quest = await vault.read.quests([0n]);
      expect(quest[3]).to.equal(0n);
    });
  });
});