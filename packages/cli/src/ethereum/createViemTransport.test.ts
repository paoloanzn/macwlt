import { describe, expect, test } from "bun:test";
import { z } from "zod";
import { EthereumClient } from "./EthereumClient";
import { createViemTransport } from "./createViemTransport";

const jsonRpcRequestSchema = z.object({
  jsonrpc: z.literal("2.0"),
  id: z.number(),
  method: z.string(),
  params: z.array(z.unknown()).optional(),
});

describe("createViemTransport", () => {
  test("performs an EVM call against the configured RPC node", async () => {
    let receivedRequest: z.infer<typeof jsonRpcRequestSchema> | undefined;
    let receivedUrl: string | undefined;
    const fetchFn = async (
      input: string | URL | Request,
      init?: RequestInit,
    ): Promise<Response> => {
      const request = new Request(input, init);
      receivedUrl = request.url;
      receivedRequest = jsonRpcRequestSchema.parse(await request.json());
      return Response.json({
        jsonrpc: "2.0",
        id: receivedRequest.id,
        result: "0xabcd",
      });
    };

    const client = EthereumClient.create(
      { rpcUrl: "https://ethereum.example/rpc", chainId: 31337 },
      (config) => createViemTransport(config, { fetchFn }),
    );
    expect(client.ok).toBe(true);
    if (!client.ok) return;

    const result = await client.value.call({
      to: "0x0000000000000000000000000000000000000001",
      data: "0x1234",
      block: "latest",
    });

    expect(result).toEqual({
      ok: true,
      value: { data: "0xabcd" },
    });
    expect(receivedUrl).toBe("https://ethereum.example/rpc");
    expect(receivedRequest?.method).toBe("eth_call");
    expect(receivedRequest?.params).toEqual([
      {
        data: "0x1234",
        to: "0x0000000000000000000000000000000000000001",
      },
      "latest",
    ]);
  });

  test("supports transaction preparation and raw broadcast operations", async () => {
    const methods: string[] = [];
    const transactionHash =
      "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const fetchFn = async (
      input: string | URL | Request,
      init?: RequestInit,
    ): Promise<Response> => {
      const request = new Request(input, init);
      const body = jsonRpcRequestSchema.parse(await request.json());
      methods.push(body.method);
      const result = responseForMethod(body.method, transactionHash);
      return Response.json({ jsonrpc: "2.0", id: body.id, result });
    };
    const client = EthereumClient.create(
      { rpcUrl: "https://ethereum.example/rpc", chainId: 31337 },
      (config) => createViemTransport(config, { fetchFn }),
    );
    if (!client.ok) throw new Error("test client configuration is invalid");

    expect(await client.value.verifyChain()).toEqual({
      ok: true,
      value: undefined,
    });
    expect(await client.value.getTransactionCount(
      "0x0000000000000000000000000000000000000001",
    )).toEqual({ ok: true, value: 2 });
    expect(await client.value.estimateGas({
      from: "0x0000000000000000000000000000000000000001",
      to: "0x0000000000000000000000000000000000000002",
      data: "0x1234",
      value: 0n,
    })).toEqual({ ok: true, value: 65_000n });
    expect(await client.value.getGasPrice()).toEqual({
      ok: true,
      value: 1_000_000_000n,
    });
    expect(await client.value.sendRawTransaction("0xc0")).toEqual({
      ok: true,
      value: transactionHash,
    });
    expect(methods).toEqual([
      "eth_chainId",
      "eth_getTransactionCount",
      "eth_estimateGas",
      "eth_gasPrice",
      "eth_sendRawTransaction",
    ]);
  });
});

function responseForMethod(
  method: string,
  transactionHash: string,
): string {
  switch (method) {
    case "eth_chainId":
      return "0x7a69";
    case "eth_getTransactionCount":
      return "0x2";
    case "eth_estimateGas":
      return "0xfde8";
    case "eth_gasPrice":
      return "0x3b9aca00";
    case "eth_sendRawTransaction":
      return transactionHash;
    default:
      throw new Error(`unexpected RPC method ${method}`);
  }
}
