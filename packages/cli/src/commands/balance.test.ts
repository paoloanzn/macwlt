import { describe, expect, test } from "bun:test";
import { commands } from "../commands";
import { parseBalance } from "./balance";

const token = "0x0000000000000000000000000000000000000001";

describe("parseBalance", () => {
  test("parses a native ETH balance request", () => {
    const result = parseBalance([
      "ETH",
      "1",
      "--rpc",
      "https://ethereum.example/rpc",
      "--path",
      "m/44/60/0/0/0",
      "--json",
    ]);

    expect(result).toEqual({
      ok: true,
      value: {
        asset: { kind: "native-eth" },
        chainId: 1,
        rpcUrl: "https://ethereum.example/rpc",
        derivationPath: "m/44/60/0/0/0",
        json: true,
      },
    });
  });

  test("parses an ERC-20 balance request using global config", () => {
    const result = parseBalance([token, "11155111"]);

    expect(result).toEqual({
      ok: true,
      value: {
        asset: { kind: "erc20", tokenAddress: token },
        chainId: 11155111,
        rpcUrl: undefined,
        derivationPath: "m",
        json: false,
      },
    });
  });

  test("rejects invalid assets, chain IDs, and options", () => {
    expect(parseBalance(["invalid", "1"])).toEqual({
      ok: false,
      error: "balance asset must be ETH or a valid Ethereum token address",
    });
    expect(parseBalance(["ETH", "0"])).toEqual({
      ok: false,
      error: "balance chain-id must be a positive integer",
    });
    expect(parseBalance(["ETH", "1", "--gas", "21000"])).toEqual({
      ok: false,
      error: "unknown balance option: --gas",
    });
  });

  test("is registered in the CLI command registry", () => {
    expect(commands.some((command) => command.name === "balance")).toBe(true);
  });
});
