import { describe, expect, test } from "bun:test";
import { z } from "zod";
import { EthereumClient } from "./EthereumClient";
import { createViemTransport } from "./createViemTransport";

const jsonRpcRequestSchema = z.object({
  jsonrpc: z.literal("2.0"),
  id: z.number(),
  method: z.string(),
  params: z.array(z.unknown()),
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
});
