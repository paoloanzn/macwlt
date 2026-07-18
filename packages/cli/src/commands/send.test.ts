import { describe, expect, test } from "bun:test";
import { commands } from "../commands";
import { parseSend } from "./send";

const token = "0x0000000000000000000000000000000000000001";
const recipient = "0x0000000000000000000000000000000000000002";

describe("parseSend", () => {
  test("parses an ERC-20 transfer", () => {
    const result = parseSend([
      "1.25",
      token,
      "11155111",
      recipient,
      "--rpc",
      "https://ethereum.example/rpc",
      "--path",
      "m/44/60/0/0/0",
      "--json",
    ]);

    expect(result).toEqual({
      ok: true,
      value: {
        amount: "1.25",
        asset: { kind: "erc20", tokenAddress: token },
        chainId: 11155111,
        recipient,
        rpcUrl: "https://ethereum.example/rpc",
        derivationPath: "m/44/60/0/0/0",
        json: true,
      },
    });
  });

  test("allows RPC resolution from global config", () => {
    const result = parseSend(["1", token, "1", recipient]);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.rpcUrl).toBeUndefined();
    expect(result.value.asset).toEqual({
      kind: "erc20",
      tokenAddress: token,
    });
    expect(result.value.derivationPath).toBe("m");
  });

  test("rejects invalid transfer inputs", () => {
    expect(parseSend(["0", token, "1", recipient])).toEqual({
      ok: false,
      error: "send amount must be greater than zero",
    });
    expect(parseSend(["1", "invalid", "1", recipient])).toEqual({
      ok: false,
      error: "send token-address must be ETH or a valid Ethereum address",
    });
    expect(parseSend(["1", token, "0", recipient])).toEqual({
      ok: false,
      error: "send chain-id must be a positive integer",
    });
    expect(parseSend(["1", token, "1", "invalid"])).toEqual({
      ok: false,
      error: "send recipient must be a valid Ethereum address",
    });
  });

  test("accepts native ETH transfers", () => {
    const result = parseSend(["0.0005", "ETH", "1", recipient]);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.asset).toEqual({ kind: "native-eth" });
  });

  test("rejects unsupported options before loading native code", () => {
    expect(parseSend([
      "1",
      token,
      "1",
      recipient,
      "--gas",
      "21000",
    ])).toEqual({
      ok: false,
      error: "unknown send option: --gas",
    });
  });

  test("is registered in the CLI command registry", () => {
    expect(commands.some((command) => command.name === "send")).toBe(true);
  });
});
