import { describe, expect, test } from "bun:test";
import { encodeAbiParameters } from "viem";
import type { EthereumConfig } from "./EthereumConfig";
import type { EvmTransport } from "./EthereumClient";
import type { EvmCallRequest } from "./EvmCall";
import { getEthereumPortfolioBalances } from "./getEthereumPortfolioBalances";
import {
  parseEthereumPortfolioConfig,
  type ConfiguredEthereumChain,
} from "./parseEthereumPortfolioConfig";

const walletAddress = "0x0000000000000000000000000000000000000001";
const usdcAddress = "0x0000000000000000000000000000000000000002";
const failingAddress = "0x0000000000000000000000000000000000000003";

describe("getEthereumPortfolioBalances", () => {
  test("reads configured assets across chains and isolates asset failures", async () => {
    const chains = configuredChains();
    const chainChecks = new Map<number, number>();

    const result = await getEthereumPortfolioBalances(
      chains,
      walletAddress,
      (config) => transportFor(config, chainChecks),
    );

    expect(result).toHaveLength(2);
    expect(chainChecks).toEqual(new Map([
      [1, 1],
      [10, 1],
    ]));

    const ethereum = result.find((chain) => chain.chain.chainId === 1);
    expect(ethereum?.status).toBe("fulfilled");
    if (ethereum?.status !== "fulfilled") return;
    expect(ethereum.assets).toHaveLength(3);
    expect(ethereum.assets[0]).toMatchObject({
      status: "fulfilled",
      symbol: "ETH",
      balance: { balance: "2" },
    });
    expect(ethereum.assets[1]).toMatchObject({
      status: "fulfilled",
      symbol: "USDC",
      balance: { balance: "1.25" },
    });
    expect(ethereum.assets[2]).toMatchObject({
      status: "failed",
      symbol: "FAIL",
      error: {
        kind: "chain-client",
        stage: "read-token-balance",
      },
    });

    const optimism = result.find((chain) => chain.chain.chainId === 10);
    expect(optimism).toMatchObject({
      status: "fulfilled",
      assets: [{
        status: "fulfilled",
        symbol: "ETH",
        balance: { balance: "0" },
      }],
    });
  });
});

function configuredChains(): readonly ConfiguredEthereumChain[] {
  const parsed = parseEthereumPortfolioConfig({
    ethereum: {
      chains: {
        "1": {
          name: "Ethereum",
          rpcUrl: "https://ethereum.example/rpc",
          nativeAsset: { symbol: "ETH" },
          assets: [
            { symbol: "USDC", address: usdcAddress },
            { symbol: "FAIL", address: failingAddress },
          ],
        },
        "10": {
          name: "Optimism",
          rpcUrl: "https://optimism.example/rpc",
          nativeAsset: { symbol: "ETH" },
          assets: [],
        },
      },
    },
  });
  if (!parsed.ok) throw new Error(parsed.error.message);
  return parsed.value;
}

function transportFor(
  config: EthereumConfig,
  chainChecks: Map<number, number>,
): EvmTransport {
  return {
    async call(request: EvmCallRequest): Promise<unknown> {
      if (request.to === failingAddress) {
        throw new Error("token unavailable");
      }
      return request.data?.startsWith("0x70a08231")
        ? { data: encodeAbiParameters([{ type: "uint256" }], [1_250_000n]) }
        : { data: encodeAbiParameters([{ type: "uint8" }], [6]) };
    },
    async getChainId(): Promise<unknown> {
      const chainId = Number(config.chainId);
      chainChecks.set(chainId, (chainChecks.get(chainId) ?? 0) + 1);
      return chainId;
    },
    async getTransactionCount(): Promise<unknown> {
      return 0;
    },
    async getBalance(): Promise<unknown> {
      return Number(config.chainId) === 1 ? 2_000_000_000_000_000_000n : 0n;
    },
    async estimateGas(): Promise<unknown> {
      return 21_000n;
    },
    async getGasPrice(): Promise<unknown> {
      return 1_000_000_000n;
    },
    async sendRawTransaction(): Promise<unknown> {
      return "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    },
  };
}
