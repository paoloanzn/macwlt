import { describe, expect, test } from "bun:test";
import { resolveEthereumRpcUrl } from "./resolveEthereumRpcUrl";

describe("resolveEthereumRpcUrl", () => {
  test("resolves a chain RPC from global config", () => {
    const result = resolveEthereumRpcUrl({
      ethereum: {
        chains: {
          "1": { rpcUrl: "https://ethereum.example/rpc" },
        },
      },
    }, 1);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(String(result.value)).toBe("https://ethereum.example/rpc");
  });

  test("distinguishes missing and invalid chain RPCs", () => {
    expect(resolveEthereumRpcUrl({}, 1)).toEqual({
      ok: false,
      error: { kind: "missing-chain-rpc", chainId: 1 },
    });
    expect(resolveEthereumRpcUrl({
      ethereum: {
        chains: {
          "1": { rpcUrl: "not a URL" },
        },
      },
    }, 1)).toEqual({
      ok: false,
      error: { kind: "invalid-chain-rpc", chainId: 1 },
    });
  });
});
