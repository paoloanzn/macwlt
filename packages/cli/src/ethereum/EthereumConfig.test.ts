import { describe, expect, test } from "bun:test";
import { parseEthereumConfig } from "./EthereumConfig";

describe("parseEthereumConfig", () => {
  test("accepts an HTTP RPC URL and positive chain ID", () => {
    const result = parseEthereumConfig({
      rpcUrl: "https://ethereum.example/rpc",
      chainId: 1,
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(String(result.value.rpcUrl)).toBe("https://ethereum.example/rpc");
    expect(Number(result.value.chainId)).toBe(1);
  });

  test("rejects non-HTTP RPC URLs", () => {
    const result = parseEthereumConfig({
      rpcUrl: "ws://ethereum.example/rpc",
      chainId: 1,
    });

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "invalid-rpc-url",
        value: "ws://ethereum.example/rpc",
      },
    });
  });

  test("rejects invalid chain IDs", () => {
    const result = parseEthereumConfig({
      rpcUrl: "https://ethereum.example/rpc",
      chainId: 0,
    });

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "invalid-chain-id",
        value: 0,
      },
    });
  });
});
