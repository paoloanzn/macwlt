import { describe, expect, test } from "bun:test";
import { encodeAbiParameters } from "viem";
import {
  EthereumClient,
  type EvmTransport,
} from "./EthereumClient";
import type { EvmCallRequest } from "./EvmCall";
import type { EvmTransactionRequest } from "./EvmTransaction";
import { encodeErc20Transfer } from "./encodeErc20Transfer";
import { sendErc20Token } from "./sendErc20Token";
import { ok } from "../result";

const tokenAddress = "0x0000000000000000000000000000000000000001";
const recipient = "0x0000000000000000000000000000000000000002";
const sender = "0x0000000000000000000000000000000000000003";
const transactionHash =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

describe("sendErc20Token", () => {
  test("prepares, signs, and broadcasts an ERC-20 transfer", async () => {
    let estimatedRequest: EvmTransactionRequest | undefined;
    let signingPreimage: Uint8Array | undefined;
    let broadcastTransaction: string | undefined;
    const client = createClient({
      async call(_request: EvmCallRequest): Promise<unknown> {
        return {
          data: encodeAbiParameters([{ type: "uint8" }], [6]),
        };
      },
      async getChainId(): Promise<unknown> {
        return 1;
      },
      async getTransactionCount(_address: string): Promise<unknown> {
        return 3;
      },
      async getBalance(): Promise<unknown> {
        return 10n ** 18n;
      },
      async estimateGas(request: EvmTransactionRequest): Promise<unknown> {
        estimatedRequest = request;
        return 65_000n;
      },
      async getGasPrice(): Promise<unknown> {
        return 1_000_000_000n;
      },
      async sendRawTransaction(transaction: string): Promise<unknown> {
        broadcastTransaction = transaction;
        return transactionHash;
      },
    });
    const signature = new Uint8Array(65);
    signature.fill(1, 0, 64);
    signature[64] = 0;

    const result = await sendErc20Token(
      client,
      {
        address: sender,
        sign(transaction: Uint8Array) {
          signingPreimage = transaction;
          return ok(signature);
        },
      },
      { tokenAddress, recipient, amount: "1.25" },
    );

    expect(result).toEqual({
      ok: true,
      value: {
        transactionHash,
        from: sender,
        amountBaseUnits: 1_250_000n,
        decimals: 6,
      },
    });
    expect(estimatedRequest).toEqual({
      from: sender,
      to: tokenAddress,
      data: encodeErc20Transfer(recipient, 1_250_000n),
      value: 0n,
    });
    expect(signingPreimage?.length).toBeGreaterThan(0);
    expect(broadcastTransaction?.startsWith("0x")).toBe(true);
  });

  test("stops before signing when the RPC node reports another chain", async () => {
    let signed = false;
    let broadcast = false;
    const transport = successfulTransport();
    transport.getChainId = async (): Promise<unknown> => 10;
    transport.sendRawTransaction = async (): Promise<unknown> => {
      broadcast = true;
      return transactionHash;
    };
    const client = createClient(transport);

    const result = await sendErc20Token(
      client,
      {
        address: sender,
        sign() {
          signed = true;
          return ok(new Uint8Array(65));
        },
      },
      { tokenAddress, recipient, amount: "1" },
    );

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "chain-client",
        stage: "verify-chain",
        error: { kind: "chain-mismatch", expected: 1, actual: 10 },
      },
    });
    expect(signed).toBe(false);
    expect(broadcast).toBe(false);
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
      return {
        data: encodeAbiParameters([{ type: "uint8" }], [18]),
      };
    },
    async getChainId(): Promise<unknown> {
      return 1;
    },
    async getTransactionCount(): Promise<unknown> {
      return 0;
    },
    async getBalance(): Promise<unknown> {
      return 10n ** 18n;
    },
    async estimateGas(): Promise<unknown> {
      return 65_000n;
    },
    async getGasPrice(): Promise<unknown> {
      return 1_000_000_000n;
    },
    async sendRawTransaction(): Promise<unknown> {
      return transactionHash;
    },
  };
}
