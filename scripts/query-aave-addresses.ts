import "dotenv/config";
import process from "node:process";

import { network } from "hardhat";
import type { Address } from "viem";

// Aave V3 interfaces (minimal for querying)
const POOL_ADDRESSES_PROVIDER_ABI = [
  {
    inputs: [],
    name: "getPool",
    outputs: [{ internalType: "address", name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

const POOL_ABI = [
  {
    inputs: [{ internalType: "address", name: "asset", type: "address" }],
    name: "getReserveData",
    outputs: [
      {
        components: [
          { internalType: "uint256", name: "configuration", type: "uint256" },
          { internalType: "uint128", name: "liquidityIndex", type: "uint128" },
          { internalType: "uint128", name: "currentLiquidityRate", type: "uint128" },
          { internalType: "uint128", name: "variableBorrowIndex", type: "uint128" },
          { internalType: "uint128", name: "currentVariableBorrowRate", type: "uint128" },
          { internalType: "uint128", name: "currentStableBorrowRate", type: "uint128" },
          { internalType: "uint40", name: "lastUpdateTimestamp", type: "uint40" },
          { internalType: "uint16", name: "id", type: "uint16" },
          { internalType: "address", name: "aTokenAddress", type: "address" },
          { internalType: "address", name: "stableDebtTokenAddress", type: "address" },
          { internalType: "address", name: "variableDebtTokenAddress", type: "address" },
          { internalType: "address", name: "interestRateStrategyAddress", type: "address" },
          { internalType: "uint128", name: "accruedToTreasury", type: "uint128" },
          { internalType: "uint128", name: "unbacked", type: "uint128" },
          { internalType: "uint128", name: "isolationModeTotalDebt", type: "uint128" },
        ],
        internalType: "struct DataTypes.ReserveData",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;

async function queryAaveAddresses() {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const chainId = await publicClient.getChainId();

  // Get addresses from environment or use defaults
  const providerAddress = (process.env.AAVE_PROVIDER_ADDRESS ||
    "0x9F7Cf9417D5251C59fE94fB9147feEe1aAd9Cea5") as Address;
  const cusdAddress = (process.env.CUSD_ADDRESS ||
    "0x765DE816845861e75A25fCA122bb6898B8B1282a") as Address;

  console.log("Querying Aave V3 addresses...");
  console.log("PoolAddressesProvider:", providerAddress);
  console.log("cUSD address:", cusdAddress);
  console.log("Chain ID:", chainId);
  
  // Celo mainnet chain ID is 42220
  if (chainId !== 42220n && chainId !== 31337n) {
    console.warn("⚠️  Warning: This script is designed for Celo mainnet (chain ID 42220)");
    console.warn("   Current chain ID:", chainId.toString());
  }
  console.log("");

  // Get Pool address from provider
  const poolAddress = await publicClient.readContract({
    address: providerAddress,
    abi: POOL_ADDRESSES_PROVIDER_ABI,
    functionName: "getPool",
  });
  console.log("✓ Pool address:", poolAddress);

  // Get reserve data for cUSD
  try {
    const reserveData = await publicClient.readContract({
      address: poolAddress,
      abi: POOL_ABI,
      functionName: "getReserveData",
      args: [cusdAddress],
    });

    console.log("\n=== Aave Reserve Data for cUSD ===");
    
    const aTokenAddress = reserveData.aTokenAddress as Address;
    const stableDebtToken = reserveData.stableDebtTokenAddress as Address;
    const variableDebtToken = reserveData.variableDebtTokenAddress as Address;
    
    console.log("aToken address (acUSD):", aTokenAddress);
    console.log("Stable Debt Token:", stableDebtToken);
    console.log("Variable Debt Token:", variableDebtToken);
    console.log("Interest Rate Strategy:", reserveData.interestRateStrategyAddress);
    console.log("Liquidity Index:", reserveData.liquidityIndex.toString());
    console.log("Current Liquidity Rate:", reserveData.currentLiquidityRate.toString());

    console.log("\n=== For Deployment ===");
    console.log("Set in your .env file:");
    console.log(`ATOKEN_ADDRESS=${aTokenAddress}`);
    console.log(`AAVE_PROVIDER_ADDRESS=${providerAddress}`);
    console.log(`ASSET_ADDRESS=${cusdAddress}`);
  } catch (error: any) {
    console.error("\n❌ Error fetching reserve data:", error.message);
    console.log("\nThis might mean:");
    console.log("1. cUSD is not listed on Aave V3 on Celo");
    console.log("2. The reserve is not active");
    console.log("3. Network/RPC connection issue");
    console.log("\nYou may need to:");
    console.log("- Check Aave docs for Celo V3 deployment");
    console.log("- Verify cUSD is actually listed on Aave V3");
    console.log("- Try querying a different asset that is confirmed to be on Aave");
    throw error;
  }
}

queryAaveAddresses().catch((error) => {
  console.error("Error querying Aave addresses:", error);
  process.exit(1);
});

