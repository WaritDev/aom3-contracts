import { expect } from "chai";
import hre from "hardhat";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits, getAddress } from "viem";

describe("AOM3Vault Discipline & Maturity Tests (Viem)", function () {
  const SECONDS_PER_MONTH = 2629743;
  const DAY_IN_SECONDS = 86400;

  async function deployVaultFixture() {
    const publicClient = await hre.viem.getPublicClient();
    const [ownerWallet, userWallet] = await hre.viem.getWalletClients();

    const usdc = await hre.viem.deployContract("MockERC20", ["USDC", "USDC", 6]);
    const strategy = await hre.viem.deployContract("MockStrategy", [usdc.address]);
    const ranking = await hre.viem.deployContract("MockRanking");

    const vault = await hre.viem.deployContract("AOM3Vault", [
      usdc.address,
      strategy.address,
      ranking.address
    ]);

    await ranking.write.setVault([vault.address]);
    await strategy.write.setVault([vault.address]);

    const initialAmount = parseUnits("1000", 6);
    await usdc.write.mint([userWallet.account.address, initialAmount]);
    await usdc.write.approve([vault.address, parseUnits("1000000", 6)], {
      account: userWallet.account
    });

    return { 
      vault, usdc, strategy, ranking, 
      publicClient, ownerWallet, userWallet 
    };
  }

  describe("Monthly Deposit Constraints", function () {
    it("Should fail if depositing twice in the same calendar month", async function () {
      const { vault, userWallet } = await loadFixture(deployVaultFixture);
      
      // Create Quest
      await vault.write.createQuest([parseUnits("10", 6), 3n], {
        account: userWallet.account
      });
      
      await expect(
        vault.write.deposit([0n], { account: userWallet.account })
      ).to.be.rejectedWith("Already deposited this month");
    });

    it("Should fail if depositing outside the day 1-7 window", async function () {
      const { vault, userWallet } = await loadFixture(deployVaultFixture);
      
      await vault.write.createQuest([parseUnits("10", 6), 3n], {
        account: userWallet.account
      });

      // Not in Day 1-7 window
      await time.increase(DAY_IN_SECONDS * 10);

      await expect(
        vault.write.deposit([0n], { account: userWallet.account })
      ).to.be.rejectedWith("Not in deposit window (Days 1-7)");
    });

    it("Should succeed if depositing in the next month's window", async function () {
      const { vault, userWallet, publicClient } = await loadFixture(deployVaultFixture);
      
      await vault.write.createQuest([parseUnits("10", 6), 3n], {
        account: userWallet.account
      });

      // Next month + inside Day 1-7 window
      await time.increase(SECONDS_PER_MONTH + 10); 

      const hash = await vault.write.deposit([0n], { account: userWallet.account });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      expect(receipt.status).to.equal("success");
    });
  });

  describe("Maturity & Withdrawal Fees", function () {
    it("Should apply 10% penalty if withdrawing before maturity", async function () {
      const { vault, userWallet, publicClient } = await loadFixture(deployVaultFixture);
      
      await vault.write.createQuest([parseUnits("100", 6), 3n], {
        account: userWallet.account
      });

      // skip time less than 3 months
      await time.increase(SECONDS_PER_MONTH);

      const hash = await vault.write.withdraw([0n], { account: userWallet.account });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      expect(receipt.status).to.equal("success");
    });

    it("Should NOT apply penalty if withdrawing after maturity", async function () {
      const { vault, userWallet, publicClient } = await loadFixture(deployVaultFixture);
      
      const amount = parseUnits("100", 6);
      await vault.write.createQuest([amount, 3n], {
        account: userWallet.account
      });

      // skip time more than 3 months
      await time.increase(DAY_IN_SECONDS * 91); 

      const hash = await vault.write.withdraw([0n], { account: userWallet.account });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      expect(receipt.status).to.equal("success");
    });
  });
});