import { describe, expect, test } from "bun:test";
import {
  EthereumClient,
  type EvmTransport,
} from "./EthereumClient";
import type { EvmTransactionRequest } from "./EvmTransaction";
import { sendNativeEth } from "./sendNativeEth";
import { ok } from "../result";

const sender = "0x0000000000000000000000000000000000000001";
const recipient = "0x0000000000000000000000000000000000000002";
const transactionHash =
  "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

describe("sendNativeEth", () => {
  test("sends an exact ETH amount when balance covers amount and gas", async () => {
    let estimatedRequest: EvmTransactionRequest | undefined;
    let signed = false;
    let broadcast = false;
    const client = createClient({
      ...successfulTransport(),
      async estimateGas(request: EvmTransactionRequest): Promise<unknown> {
        estimatedRequest = request;
        return 21_000n;
      },
      async sendRawTransaction(): Promise<unknown> {
        broadcast = true;
        return transactionHash;
      },
    });
    const signature = new Uint8Array(65);
    signature.fill(1, 0, 64);

    const result = await sendNativeEth(
      client,
      {
        address: sender,
        sign() {
          signed = true;
          return ok(signature);
        },
      },
      { recipient, amount: "0.0005" },
    );

    expect(result).toEqual({
      ok: true,
      value: {
        transactionHash,
        from: sender,
        amountWei: 500_000_000_000_000n,
        feeWei: 21_000_000_000_000n,
        balanceWei: 1_000_000_000_000_000n,
      },
    });
    expect(estimatedRequest).toEqual({
      from: sender,
      to: recipient,
      value: 500_000_000_000_000n,
    });
    expect(signed).toBe(true);
    expect(broadcast).toBe(true);
  });

  test("does not sign when balance cannot cover amount plus gas", async () => {
    let signed = false;
    let broadcast = false;
    const client = createClient({
      ...successfulTransport(),
      async getBalance(): Promise<unknown> {
        return 510_000_000_000_000n;
      },
      async sendRawTransaction(): Promise<unknown> {
        broadcast = true;
        return transactionHash;
      },
    });

    const result = await sendNativeEth(
      client,
      {
        address: sender,
        sign() {
          signed = true;
          return ok(new Uint8Array(65));
        },
      },
      { recipient, amount: "0.0005" },
    );

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "insufficient-funds",
        balanceWei: 510_000_000_000_000n,
        requiredWei: 521_000_000_000_000n,
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
      return { data: "0x" };
    },
    async getChainId(): Promise<unknown> {
      return 1;
    },
    async getTransactionCount(): Promise<unknown> {
      return 0;
    },
    async getBalance(): Promise<unknown> {
      return 1_000_000_000_000_000n;
    },
    async estimateGas(): Promise<unknown> {
      return 21_000n;
    },
    async getGasPrice(): Promise<unknown> {
      return 1_000_000_000n;
    },
    async sendRawTransaction(): Promise<unknown> {
      return transactionHash;
    },
  };
}
