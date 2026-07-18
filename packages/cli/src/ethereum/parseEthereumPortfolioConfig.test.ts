import { describe, expect, test } from "bun:test";
import defaultConfigInput from "../../config.default.json";
import { parseGlobalConfigData } from "../config";
import { parseEthereumPortfolioConfig } from "./parseEthereumPortfolioConfig";

describe("parseEthereumPortfolioConfig", () => {
  test("parses every chain and asset in the packaged default", () => {
    const globalConfig = parseGlobalConfigData(defaultConfigInput);
    if (!globalConfig.ok) throw new Error("packaged default is invalid JSON config");

    const result = parseEthereumPortfolioConfig(globalConfig.value);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.map((chain) => chain.chainId).sort((a, b) => a - b)).toEqual([
      1,
      10,
      56,
      137,
      8453,
      42161,
      43114,
    ]);
    expect(Object.fromEntries(result.value.map((chain) => [
      chain.chainId,
      {
        native: chain.nativeSymbol,
        assets: chain.assets.map((asset) => asset.symbol),
      },
    ]))).toEqual({
      1: { native: "ETH", assets: ["USDC", "USDT", "WETH"] },
      10: { native: "ETH", assets: ["USDC", "USDT", "WETH"] },
      56: { native: "BNB", assets: ["USDC", "USDT", "WBNB"] },
      137: { native: "POL", assets: ["USDC", "USDT", "WETH"] },
      8453: { native: "ETH", assets: ["USDC", "WETH"] },
      42161: { native: "ETH", assets: ["USDC", "USDT", "WETH"] },
      43114: { native: "AVAX", assets: ["USDC", "USDT", "WAVAX"] },
    });
  });

  test("rejects malformed chain IDs, assets, and duplicate symbols", () => {
    expect(parseEthereumPortfolioConfig({
      ethereum: {
        chains: {
          invalid: validChain(),
        },
      },
    })).toEqual({
      ok: false,
      error: {
        kind: "invalid-portfolio-config",
        message: "ethereum.chains.invalid: invalid chain ID",
      },
    });

    const invalidAddress = parseEthereumPortfolioConfig({
      ethereum: {
        chains: {
          "1": {
            ...validChain(),
            assets: [{ symbol: "USDC", address: "invalid" }],
          },
        },
      },
    });
    expect(invalidAddress.ok).toBe(false);
    if (!invalidAddress.ok) {
      expect(invalidAddress.error.message).toContain("invalid Ethereum address");
    }

    expect(parseEthereumPortfolioConfig({
      ethereum: {
        chains: {
          "1": {
            ...validChain(),
            assets: [
              {
                symbol: "USDC",
                address: "0x0000000000000000000000000000000000000001",
              },
              {
                symbol: "usdc",
                address: "0x0000000000000000000000000000000000000002",
              },
            ],
          },
        },
      },
    })).toEqual({
      ok: false,
      error: {
        kind: "invalid-portfolio-config",
        message: "ethereum.chains.1.assets: duplicate symbol usdc",
      },
    });
  });
});

function validChain() {
  return {
    name: "Ethereum",
    rpcUrl: "https://ethereum.example/rpc",
    nativeAsset: { symbol: "ETH" },
    assets: [],
  };
}
