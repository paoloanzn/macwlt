import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { resolveTransfer } from "../skills/sending-evm-assets/scripts/resolve-transfer.mjs";

const recipient = "0x0000000000000000000000000000000000000001";
const usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
let directory;
let configPath;

before(async () => {
  directory = await mkdtemp(join(tmpdir(), "mac-wallet-skill-"));
  configPath = join(directory, "config.json");
  await writeFile(configPath, JSON.stringify({
    ethereum: {
      chains: {
        "1": {
          name: "Ethereum Mainnet",
          rpcUrl: "https://ethereum.example",
          nativeAsset: { symbol: "ETH" },
          assets: [],
        },
        "8453": {
          name: "Base",
          rpcUrl: "https://base.example",
          nativeAsset: { symbol: "ETH" },
          assets: [{ symbol: "USDC", address: usdc }],
        },
      },
    },
  }));
});

after(async () => {
  await rm(directory, { recursive: true, force: true });
});

test("resolves a natural Base USDC transfer into macwlt command arrays", async () => {
  const result = await resolveTransfer({
    amount: "10",
    asset: "USDC",
    chain: "Base",
    recipient,
    configPath,
  });

  assert.deepEqual(result.chain, {
    chainId: 8453,
    name: "Base",
    nativeSymbol: "ETH",
  });
  assert.deepEqual(result.asset, {
    kind: "erc20",
    symbol: "USDC",
    tokenAddress: usdc,
  });
  assert.deepEqual(result.commands.send, [
    "macwlt",
    "send",
    "10",
    usdc,
    "8453",
    recipient,
    "--json",
  ]);
});

test("accepts chain aliases and preserves an explicit derivation path", async () => {
  const result = await resolveTransfer({
    amount: "0.25",
    asset: "eth",
    chain: "mainnet",
    recipient,
    derivationPath: "m/44'/60'/0'/0/0",
    configPath,
  });

  assert.equal(result.chain.chainId, 1);
  assert.deepEqual(result.asset, { kind: "native", symbol: "ETH" });
  assert.deepEqual(result.commands.send.slice(-3), [
    "--path",
    "m/44'/60'/0'/0/0",
    "--json",
  ]);
});

test("rejects unconfigured assets and invalid recipients", async () => {
  await assert.rejects(
    resolveTransfer({
      amount: "10",
      asset: "USDT",
      chain: "Base",
      recipient,
      configPath,
    }),
    /asset USDT is not configured on Base/,
  );
  await assert.rejects(
    resolveTransfer({
      amount: "10",
      asset: "USDC",
      chain: "Base",
      recipient: "not-an-address",
      configPath,
    }),
    /recipient must be a 20-byte/,
  );
  await assert.rejects(
    resolveTransfer({
      amount: "10",
      asset: "USDC",
      chain: "Base",
      recipient: "0x0000000000000000000000000000000000000000",
      configPath,
    }),
    /recipient must not be the zero address/,
  );
});
