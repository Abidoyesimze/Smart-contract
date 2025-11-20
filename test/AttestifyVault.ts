import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeFunctionData } from "viem";

describe("AttestifyVault", async () => {
  const { viem } = await network.connect();
  const wallets = await viem.getWalletClients();
  const [deployer, alice, bob, carol] = wallets;
  const ONE = 10n ** 18n;

  async function deployFixture() {
    const asset = await viem.deployContract("MockERC20", ["Mock USD", "MUSD"]);
    const verifier = await viem.deployContract("MockVerifier");
    const strategy = await viem.deployContract("MockStrategy", [asset.address]);
    const vaultImpl = await viem.deployContract("AttestifyVault");
    const maxUser = 1_000_000n * ONE;
    const maxTotal = 10_000_000n * ONE;

    const initCallData = encodeFunctionData({
      abi: vaultImpl.abi,
      functionName: "initialize",
      args: [asset.address, strategy.address, verifier.address, maxUser, maxTotal],
    });

    const proxy = await viem.deployContract("TestProxy", [
      vaultImpl.address,
      initCallData,
    ]);

    const vault = await viem.getContractAt("AttestifyVault", proxy.address);

    await strategy.write.setVault([vault.address], { account: deployer.account });

    const mintAmount = 100_000n * ONE;
    for (const wallet of [deployer, alice, bob, carol]) {
      await asset.write.mint([wallet.account.address, mintAmount], {
        account: deployer.account,
      });
    }

    return { asset, verifier, strategy, vault };
  }

  async function verifyUsers(verifier: any, users: string[]) {
    for (const user of users) {
      await verifier.write.setVerified([user, true], {
        account: deployer.account,
      });
    }
  }

  async function expectRevert(promise: Promise<unknown>, reason?: string) {
    await assert.rejects(promise, (error: any) => {
      const errorName =
        error?.cause?.data?.errorName ||
        error?.cause?.cause?.errorName ||
        error?.errorName;
      if (reason && errorName && errorName === reason) {
        return true;
      }
      const parts = [
        error?.message,
        error?.shortMessage,
        error?.details,
        error?.cause?.message,
        error?.cause?.shortMessage,
        error?.cause?.details,
        error?.cause?.cause?.details,
        String(error ?? ""),
      ]
        .filter(Boolean)
        .join(" ");
      if (!reason) return true;
      const matched = parts.includes(reason);
      return matched;
    });
  }

  it("blocks unverified deposits", async () => {
    const { asset, verifier, vault } = await deployFixture();
    const depositAmount = 100n * ONE;

    await asset.write.approve([vault.address, depositAmount], {
      account: alice.account,
    });

    await assert.rejects(
      vault.write.deposit([depositAmount], { account: alice.account }),
    );

    await verifyUsers(verifier, [alice.account.address]);

    await vault.write.deposit([depositAmount], { account: alice.account });
    const balance = await vault.read.balanceOf([alice.account.address]);
    assert.equal(balance, depositAmount);
  });

  it("protects share price against donation manipulation", async () => {
    const { asset, verifier, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address, bob.account.address]);

    const smallDeposit = 1n * ONE;
    const donation = 1_000n * ONE;
    const bobDeposit = 2_000n * ONE;

    await asset.write.approve([vault.address, smallDeposit], {
      account: alice.account,
    });
    await vault.write.deposit([smallDeposit], { account: alice.account });

    await asset.write.transfer([vault.address, donation], {
      account: deployer.account,
    });

    await asset.write.approve([vault.address, bobDeposit], {
      account: bob.account,
    });
    await vault.write.deposit([bobDeposit], { account: bob.account });

    const bobBalance = await vault.read.balanceOf([bob.account.address]);
    const tolerance = 2n;
    assert.ok(bobBalance >= bobDeposit - tolerance);
  });

  it("enforces minimum assets out on withdrawals", async () => {
    const { asset, verifier, vault } = await deployFixture();
    await verifyUsers(verifier, [bob.account.address]);

    const depositAmount = 500n * ONE;

    await asset.write.approve([vault.address, depositAmount], {
      account: bob.account,
    });
    await vault.write.deposit([depositAmount], { account: bob.account });

    await assert.rejects(
      bob.writeContract({
        address: vault.address,
        abi: vault.abi,
        functionName: "withdraw",
        args: [depositAmount / 2n, depositAmount / 2n + 1n],
      }),
    );
  });

  it("allows withdrawing entire balance via withdrawAll", async () => {
    const { asset, verifier, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address]);

    const depositAmount = 800n * ONE;

    await asset.write.approve([vault.address, depositAmount], {
      account: alice.account,
    });
    await vault.write.deposit([depositAmount], { account: alice.account });

    await vault.write.withdrawAll({ account: alice.account });

    const shareBalance = await vault.read.shares([alice.account.address]);
    const assetBalance = await vault.read.balanceOf([alice.account.address]);

    assert.equal(shareBalance, 0n);
    assert.equal(assetBalance, 0n);
  });

  it("tops up reserves when they fall below the target ratio", async () => {
    const { asset, verifier, strategy, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address]);

    const depositAmount = 1_000n * ONE;

    await asset.write.approve([vault.address, depositAmount], {
      account: alice.account,
    });
    await vault.write.deposit([depositAmount], { account: alice.account });

    const withdrawAmount = 200n * ONE;

    await vault.write.withdraw([withdrawAmount], { account: alice.account });

    const reserveBalance = await asset.read.balanceOf([vault.address]);
    const strategyBalance = await strategy.read.totalAssets();
    const totalAssets = await vault.read.totalAssets();
    const targetReserve = (totalAssets * 10n) / 100n;

    assert.equal(totalAssets, depositAmount - withdrawAmount);
    assert.ok(reserveBalance >= targetReserve);
    assert.equal(strategyBalance, totalAssets - reserveBalance);
  });

  it("enforces deposit limits and pause controls", async () => {
    const { asset, verifier, vault } = await deployFixture();
    await verifyUsers(verifier, [
      alice.account.address,
      bob.account.address,
    ]);

    const userLimit = 500n * ONE;
    const totalLimit = 1_000n * ONE;
    await vault.write.setLimits([userLimit, totalLimit], {
      account: deployer.account,
    });

    await asset.write.approve([vault.address, 600n * ONE], {
      account: alice.account,
    });
    await expectRevert(
      vault.write.deposit([600n * ONE], { account: alice.account }),
    );
    const aliceSharesAfterFail = await vault.read.shares([
      alice.account.address,
    ]);
    assert.equal(aliceSharesAfterFail, 0n);

    await asset.write.approve([vault.address, userLimit], {
      account: alice.account,
    });
    await vault.write.deposit([userLimit], { account: alice.account });

    await asset.write.approve([vault.address, 600n * ONE], {
      account: bob.account,
    });
    await expectRevert(
      vault.write.deposit([600n * ONE], { account: bob.account }),
    );
    const totalAssetsAfterFail = await vault.read.totalAssets();
    assert.equal(totalAssetsAfterFail, userLimit);

    await vault.write.pause({ account: deployer.account });
    await expectRevert(
      vault.write.deposit([100n * ONE], { account: bob.account }),
    );

    await vault.write.unpause({ account: deployer.account });
    await vault.write.setLimits([userLimit, 2_000n * ONE], {
      account: deployer.account,
    });
    await vault.write.deposit([400n * ONE], { account: bob.account });
  });

  it("allows owner or delegated rebalancer to maintain reserves", async () => {
    const { asset, verifier, strategy, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address]);

    const depositAmount = 2_000n * ONE;
    await asset.write.approve([vault.address, depositAmount], {
      account: alice.account,
    });
    await vault.write.deposit([depositAmount], { account: alice.account });

    await expectRevert(
      vault.write.rebalance({ account: carol.account }),
      "Unauthorized",
    );

    await vault.write.setRebalancer([bob.account.address], {
      account: deployer.account,
    });

    await asset.write.transfer([vault.address, 5_000n * ONE], {
      account: deployer.account,
    });

    await vault.write.rebalance({ account: bob.account });

    const totalAssets = await vault.read.totalAssets();
    const reserveBalance = await asset.read.balanceOf([vault.address]);
    const targetReserve = (totalAssets * 10n) / 100n;
    assert.ok(reserveBalance >= targetReserve);
    assert.ok(reserveBalance <= targetReserve * 2n);

    const strategyBalance = await strategy.read.totalAssets();
    assert.equal(strategyBalance, totalAssets - reserveBalance);
  });

  it("supports emergency withdrawals when paused", async () => {
    const { asset, verifier, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address]);

    const depositAmount = 1_000n * ONE;
    await asset.write.approve([vault.address, depositAmount], {
      account: alice.account,
    });
    await vault.write.deposit([depositAmount], { account: alice.account });

    await vault.write.pause({ account: deployer.account });

    const reserveBalance = await asset.read.balanceOf([vault.address]);
    const ownerBefore = await asset.read.balanceOf([
      deployer.account.address,
    ]);

    await vault.write.emergencyWithdraw([asset.address, reserveBalance], {
      account: deployer.account,
    });

    const ownerAfter = await asset.read.balanceOf([deployer.account.address]);
    assert.equal(ownerAfter - ownerBefore, reserveBalance);
  });

  it("lets the owner rotate verifier and strategy contracts", async () => {
    const { asset, verifier, strategy, vault } = await deployFixture();
    await verifyUsers(verifier, [alice.account.address]);

    const firstDeposit = 500n * ONE;
    await asset.write.approve([vault.address, firstDeposit], {
      account: alice.account,
    });
    await vault.write.deposit([firstDeposit], { account: alice.account });

    const newVerifier = await viem.deployContract("MockVerifier");
    await vault.write.setVerifier([newVerifier.address], {
      account: deployer.account,
    });

    await expectRevert(
      vault.write.deposit([100n * ONE], { account: alice.account }),
      "NotVerified",
    );

    await newVerifier.write.setVerified([alice.account.address, true], {
      account: deployer.account,
    });

    await asset.write.approve([vault.address, 200n * ONE], {
      account: alice.account,
    });
    await vault.write.deposit([200n * ONE], { account: alice.account });

    const newStrategy = await viem.deployContract("MockStrategy", [
      asset.address,
    ]);
    await vault.write.setStrategy([newStrategy.address], {
      account: deployer.account,
    });
    await newStrategy.write.setVault([vault.address], {
      account: deployer.account,
    });

    await newVerifier.write.setVerified([bob.account.address, true], {
      account: deployer.account,
    });
    await asset.write.approve([vault.address, 1_000n * ONE], {
      account: bob.account,
    });
    await vault.write.deposit([1_000n * ONE], { account: bob.account });

    const newStrategyAssets = await newStrategy.read.totalAssets();
    assert.equal(newStrategyAssets, 900n * ONE);
  });

  it("restricts admin functions to the owner", async () => {
    const { vault } = await deployFixture();

    await expectRevert(
      vault.write.pause({ account: alice.account }),
      "OwnableUnauthorizedAccount",
    );
    await expectRevert(
      vault.write.setLimits([1n, 1n], { account: alice.account }),
      "OwnableUnauthorizedAccount",
    );
    await expectRevert(
      vault.write.setStrategy([alice.account.address], {
        account: alice.account,
      }),
      "OwnableUnauthorizedAccount",
    );
    await expectRevert(
      vault.write.setVerifier([alice.account.address], {
        account: alice.account,
      }),
      "OwnableUnauthorizedAccount",
    );
    await expectRevert(
      vault.write.emergencyWithdraw([alice.account.address, 1n], {
        account: alice.account,
      }),
      "OwnableUnauthorizedAccount",
    );
  });
});

