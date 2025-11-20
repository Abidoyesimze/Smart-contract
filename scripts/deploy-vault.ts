import "dotenv/config";
import process from "node:process";

import { network } from "hardhat";
import { encodeFunctionData, parseUnits } from "viem";
import type { Address } from "viem";

type DeployConfig = {
  asset: Address;
  aToken: Address;
  addressesProvider: Address;
  verifier: Address;
  maxUserDeposit: bigint;
  maxTotalDeposit: bigint;
  assetDecimals: number;
  rebalancer?: Address;
  authorizeVaultOnVerifier: boolean;
};

function requireAddress(name: string): Address {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var ${name}`);
  }
  if (!value.startsWith("0x") || value.length !== 42) {
    throw new Error(`Env var ${name} must be a 20-byte hex address`);
  }
  return value as Address;
}

function getAmountEnv(name: string, decimals: number, fallback: string): bigint {
  const raw = process.env[name] ?? fallback;
  return parseUnits(raw, decimals);
}

function loadConfig(): DeployConfig {
  const assetDecimals = Number(process.env.ASSET_DECIMALS ?? "18");
  return {
    asset: requireAddress("ASSET_ADDRESS"),
    aToken: requireAddress("ATOKEN_ADDRESS"),
    addressesProvider: requireAddress("AAVE_PROVIDER_ADDRESS"),
    verifier: requireAddress("VERIFIER_ADDRESS"),
    maxUserDeposit: getAmountEnv("MAX_USER_DEPOSIT", assetDecimals, "1000"),
    maxTotalDeposit: getAmountEnv("MAX_TOTAL_DEPOSIT", assetDecimals, "10000"),
    assetDecimals,
    rebalancer: process.env.REBALANCER_ADDRESS as Address | undefined,
    authorizeVaultOnVerifier: process.env.AUTHORIZE_VAULT === "true",
  };
}

const params = loadConfig();
const { viem } = await network.connect();
const publicClient = await viem.getPublicClient();
const [deployer] = await viem.getWalletClients();

console.log("Deploying with account:", deployer.account.address);
console.log("Chain id:", await publicClient.getChainId());

console.log("Deploying AaveV3Strategy...");
const strategy = await viem.deployContract("AaveV3Strategy", {
  account: deployer.account,
  args: [params.asset, params.aToken, params.addressesProvider],
});

console.log("Deploying AttestifyVault implementation...");
const vaultImplementation = await viem.deployContract("AttestifyVault", {
  account: deployer.account,
});

const initData = encodeFunctionData({
  abi: vaultImplementation.abi,
  functionName: "initialize",
  args: [
    params.asset,
    strategy.address,
    params.verifier,
    params.maxUserDeposit,
    params.maxTotalDeposit,
  ],
});

console.log("Deploying ERC1967 proxy...");
const proxy = await viem.deployContract("TestProxy", {
  account: deployer.account,
  args: [vaultImplementation.address, initData],
});

const vault = await viem.getContractAt("AttestifyVault", proxy.address);
console.log("Vault proxy deployed at:", vault.address);

console.log("Linking strategy to vault...");
await strategy.write.setVault([vault.address], {
  account: deployer.account,
});

if (params.rebalancer && params.rebalancer !== deployer.account.address) {
  console.log("Setting custom rebalancer:", params.rebalancer);
  await vault.write.setRebalancer([params.rebalancer], {
    account: deployer.account,
  });
}

if (params.authorizeVaultOnVerifier) {
  console.log("Authorizing vault on verifier...");
  const verifier = await viem.getContractAt("SelfProtocolVerifier", params.verifier);
  await verifier.write.authorizeCaller([vault.address], {
    account: deployer.account,
  });
}

console.log("\nDeployment complete:");
console.log("- Strategy:", strategy.address);
console.log("- Vault Implementation:", vaultImplementation.address);
console.log("- Vault Proxy:", vault.address);

console.log("\nRemember to:");
console.log("1. Fund the vault with reserves if needed.");
console.log("2. Verify contracts on the block explorer.");
console.log("3. Configure rebalancer/treasury roles and deposit limits as required.");

