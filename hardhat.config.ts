import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";
import process from "node:process";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    celoMainnet: {
      type: "http",
      chainType: "l1",
      url: process.env.CELO_MAINNET_RPC_URL || "https://forno.celo.org",
      accounts: process.env.CELO_PRIVATE_KEY ? [process.env.CELO_PRIVATE_KEY] : [],
      chainId: 42220,
    },
    celoAlfajores: {
      type: "http",
      chainType: "l1",
      url: process.env.CELO_ALFAJORES_RPC_URL || "https://alfajores-forno.celo-testnet.org",
      accounts: process.env.CELO_PRIVATE_KEY ? [process.env.CELO_PRIVATE_KEY] : [],
      chainId: 44787,
    },
  },
});
