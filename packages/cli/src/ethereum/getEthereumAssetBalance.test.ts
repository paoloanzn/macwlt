import { describe, expect, test } from "bun:test";
import { encodeAbiParameters } from "viem";
import {
  EthereumClient,
  type EvmTransport,
} from "./EthereumClient";
import type { EvmCallRequest } from "./EvmCall";
import { getEthereumAssetBalance } from "./getEthereumAssetBalance";

const walletAddress = "0x0000000000000000000000000000000000000001";
const tokenAddress = "0x0000000000000000000000000000000000000002";

describe("getEthereumAssetBalance", () => {
  test("reads and formats the native ETH balance", async () => {
    const client = createClient({
      ...successfulTransport(),
      async getBalance(address: string): Promise<unknown> {
        expect(address).toBe(walletAddress);
        return 498_735_951_347_000n;
      },
    });

    const result = await getEthereumAssetBalance(
      client,
      walletAddress,
      { kind: "native-eth" },
    );

    expect(result).toEqual({
      ok: true,
      value: {
        kind: "native-eth",
        address: walletAddress,
        balance: "0.000498735951347",
        balanceBaseUnits: 498_735_951_347_000n,
        decimals: 18,
      },
    });
  });

  test("reads and formats an ERC-20 balance using token decimals", async () => {
    const calls: EvmCallRequest[] = [];
    const client = createClient({
      ...successfulTransport(),
      async call(request: EvmCallRequest): Promise<unknown> {
        calls.push(request);
        return request.data?.startsWith("0x70a08231")
          ? { data: encodeAbiParameters([{ type: "uint256" }], [1_250_000n]) }
          : { data: encodeAbiParameters([{ type: "uint8" }], [6]) };
      },
    });

    const result = await getEthereumAssetBalance(
      client,
      walletAddress,
      { kind: "erc20", tokenAddress },
    );

    expect(result).toEqual({
      ok: true,
      value: {
        kind: "erc20",
        address: walletAddress,
        tokenAddress,
        balance: "1.25",
        balanceBaseUnits: 1_250_000n,
        decimals: 6,
      },
    });
    expect(calls).toHaveLength(2);
    expect(calls.every((call) => call.to === tokenAddress)).toBe(true);
  });

  test("rejects an RPC node for a different chain before reading balance", async () => {
    let balanceRead = false;
    const client = createClient({
      ...successfulTransport(),
      async getChainId(): Promise<unknown> {
        return 10;
      },
      async getBalance(): Promise<unknown> {
        balanceRead = true;
        return 0n;
      },
    });

    const result = await getEthereumAssetBalance(
      client,
      walletAddress,
      { kind: "native-eth" },
    );

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "chain-client",
        stage: "verify-chain",
        error: { kind: "chain-mismatch", expected: 1, actual: 10 },
      },
    });
    expect(balanceRead).toBe(false);
  });
});

function createClient(transport: EvmTransport): EthereumClient {
  const result = EthereumClient.create(
    { rpcUrl: "https://ethereum.example/rpc", chainId: 1 },
    () => transport,
  );
  if (!result.ok) throw new Error("test client configuration is invalid");
  return result.value;
}

function successfulTransport(): EvmTransport {
  return {
    async call(): Promise<unknown> {
      return { data: "0x" };
    },
    async getChainId(): Promise<unknown> {
      return 1;
    },
    async getTransactionCount(): Promise<unknown> {
      return 0;
    },
    async getBalance(): Promise<unknown> {
      return 0n;
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
