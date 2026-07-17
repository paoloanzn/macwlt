import { describe, expect, test } from "bun:test";
import type { EthereumConfig } from "./EthereumConfig";
import {
  EthereumClient,
  type EvmCallTransport,
} from "./EthereumClient";
import type { EvmCallRequest } from "./EvmCall";

const validRequest: EvmCallRequest = {
  to: "0x0000000000000000000000000000000000000001",
  data: "0x1234",
};

describe("EthereumClient", () => {
  test("composes a transport using the validated RPC URL and chain ID", async () => {
    let receivedConfig: EthereumConfig | undefined;
    let receivedRequest: EvmCallRequest | undefined;
    const result = EthereumClient.create(
      { rpcUrl: "https://ethereum.example/rpc", chainId: 11155111 },
      (config) => {
        receivedConfig = config;
        return {
          async call(request: EvmCallRequest): Promise<unknown> {
            receivedRequest = request;
            return { data: "0xabcd" };
          },
        };
      },
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const call = await result.value.call(validRequest);

    expect(String(receivedConfig?.rpcUrl)).toBe("https://ethereum.example/rpc");
    expect(Number(receivedConfig?.chainId)).toBe(11155111);
    expect(receivedRequest).toEqual(validRequest);
    expect(call).toEqual({ ok: true, value: { data: "0xabcd" } });
  });

  test("does not create a transport for invalid configuration", () => {
    let factoryCalled = false;
    const result = EthereumClient.create(
      { rpcUrl: "not a URL", chainId: 1 },
      () => {
        factoryCalled = true;
        return successfulTransport();
      },
    );

    expect(factoryCalled).toBe(false);
    expect(result).toEqual({
      ok: false,
      error: { kind: "invalid-rpc-url", value: "not a URL" },
    });
  });

  test("does not invoke the transport for an invalid call", async () => {
    let transportCalled = false;
    const client = createClient({
      async call(): Promise<unknown> {
        transportCalled = true;
        return { data: "0x" };
      },
    });

    const result = await client.call({
      to: "0xinvalid",
      data: "0x1234",
    });

    expect(transportCalled).toBe(false);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error.kind).toBe("invalid-request");
  });

  test("rejects malformed data returned by a transport", async () => {
    const client = createClient({
      async call(): Promise<unknown> {
        return { data: "not hex" };
      },
    });

    const result = await client.call(validRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error.kind).toBe("invalid-response");
  });

  test("models transport failures", async () => {
    const cause = new Error("RPC unavailable");
    const client = createClient({
      async call(): Promise<unknown> {
        throw cause;
      },
    });

    const result = await client.call(validRequest);

    expect(result).toEqual({
      ok: false,
      error: { kind: "transport-failed", cause },
    });
  });

  test("reports missing transaction transport capability", async () => {
    const client = createClient(successfulTransport());

    expect(await client.verifyChain()).toEqual({
      ok: false,
      error: { kind: "unsupported-transport" },
    });
  });
});

function createClient(transport: EvmCallTransport): EthereumClient {
  const result = EthereumClient.create(
    { rpcUrl: "https://ethereum.example/rpc", chainId: 1 },
    () => transport,
  );
  if (!result.ok) throw new Error("test client configuration is invalid");
  return result.value;
}

function successfulTransport(): EvmCallTransport {
  return {
    async call(): Promise<unknown> {
      return { data: "0x" };
    },
  };
}
