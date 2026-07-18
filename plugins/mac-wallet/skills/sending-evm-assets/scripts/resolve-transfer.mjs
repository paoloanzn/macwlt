#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const amountPattern = /^(?:0|[1-9]\d*)(?:\.\d+)?$/;
const derivationPathPattern = /^m(?:\/(?:0|[1-9]\d*)(?:')?)*$/;
const chainAliases = new Map([
  ["1", ["ethereum", "ethereummainnet", "mainnet"]],
  ["10", ["op", "optimism", "opmainnet"]],
  ["56", ["bnb", "bsc", "bnbsmartchain"]],
  ["137", ["polygon", "polygonpos"]],
  ["8453", ["base"]],
  ["42161", ["arbitrum", "arbitrumone"]],
  ["43114", ["avalanche", "avax", "avalanchecchain"]],
]);

export async function resolveTransfer(input) {
  validateRequest(input);
  const configPath = input.configPath ??
    join(homedir(), ".config", "macwlt", "config.json");
  const config = await loadConfig(configPath);
  const chain = resolveChain(config, input.chain);
  const asset = resolveAsset(chain, input.asset);
  const pathArguments = input.derivationPath === undefined
    ? []
    : ["--path", input.derivationPath];

  const balanceCommand = [
    "macwlt",
    "balance",
    asset.argument,
    String(chain.chainId),
    ...pathArguments,
    "--json",
  ];
  const gasBalanceCommand = [
    "macwlt",
    "balance",
    "ETH",
    String(chain.chainId),
    ...pathArguments,
    "--json",
  ];
  const sendCommand = [
    "macwlt",
    "send",
    input.amount,
    asset.argument,
    String(chain.chainId),
    input.recipient,
    ...pathArguments,
    "--json",
  ];

  return {
    amount: input.amount,
    recipient: input.recipient,
    derivationPath: input.derivationPath ?? "m",
    configPath,
    chain: {
      chainId: chain.chainId,
      name: chain.name,
      nativeSymbol: chain.nativeSymbol,
    },
    asset: {
      kind: asset.kind,
      symbol: asset.symbol,
      ...(asset.tokenAddress === undefined
        ? {}
        : { tokenAddress: asset.tokenAddress }),
    },
    commands: {
      balance: balanceCommand,
      gasBalance: gasBalanceCommand,
      send: sendCommand,
    },
  };
}

function validateRequest(input) {
  if (!amountPattern.test(input.amount) || !/[1-9]/.test(input.amount)) {
    throw new Error("amount must be a positive decimal without exponent notation");
  }
  if (!addressPattern.test(input.recipient)) {
    throw new Error("recipient must be a 20-byte 0x-prefixed EVM address");
  }
  if (/^0x0{40}$/i.test(input.recipient)) {
    throw new Error("recipient must not be the zero address");
  }
  if (input.asset.trim().length === 0) {
    throw new Error("asset must not be empty");
  }
  if (input.chain.trim().length === 0) {
    throw new Error("chain must not be empty");
  }
  if (
    input.derivationPath !== undefined &&
    !derivationPathPattern.test(input.derivationPath)
  ) {
    throw new Error("derivation path must use the form m/44'/60'/0'/0/0");
  }
}

async function loadConfig(configPath) {
  let input;
  try {
    input = JSON.parse(await readFile(configPath, "utf8"));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`cannot read macwlt config ${configPath}: ${message}`);
  }
  if (!isRecord(input) || !isRecord(input.ethereum) ||
      !isRecord(input.ethereum.chains)) {
    throw new Error(
      `invalid macwlt config ${configPath}: ethereum.chains must be an object`,
    );
  }
  return input.ethereum.chains;
}

function resolveChain(chains, requestedChain) {
  const requested = normalize(requestedChain);
  const matches = [];

  for (const [chainIdValue, value] of Object.entries(chains)) {
    const chainId = Number(chainIdValue);
    if (!Number.isSafeInteger(chainId) || chainId <= 0 || !isRecord(value)) {
      continue;
    }
    const name = requiredString(value.name, `chain ${chainId} name`);
    const aliases = chainAliases.get(String(chainId)) ?? [];
    if (
      requested === String(chainId) ||
      requested === normalize(name) ||
      aliases.includes(requested)
    ) {
      matches.push(parseChain(chainId, name, value));
    }
  }

  if (matches.length === 0) {
    const available = Object.entries(chains)
      .filter(([, value]) => isRecord(value) && typeof value.name === "string")
      .map(([chainId, value]) => `${value.name} (${chainId})`)
      .join(", ");
    throw new Error(
      `chain ${requestedChain} is not configured` +
      (available.length === 0 ? "" : `; available chains: ${available}`),
    );
  }
  if (matches.length > 1) {
    throw new Error(`chain ${requestedChain} matches multiple configured chains`);
  }
  return matches[0];
}

function parseChain(chainId, name, value) {
  if (!isRecord(value.nativeAsset)) {
    throw new Error(`chain ${chainId} nativeAsset must be an object`);
  }
  const nativeSymbol = requiredString(
    value.nativeAsset.symbol,
    `chain ${chainId} native asset symbol`,
  );
  if (!Array.isArray(value.assets)) {
    throw new Error(`chain ${chainId} assets must be an array`);
  }

  const assets = value.assets.map((asset, index) => {
    if (!isRecord(asset)) {
      throw new Error(`chain ${chainId} asset ${index} must be an object`);
    }
    const symbol = requiredString(
      asset.symbol,
      `chain ${chainId} asset ${index} symbol`,
    );
    const address = requiredString(
      asset.address,
      `chain ${chainId} asset ${index} address`,
    );
    if (!addressPattern.test(address)) {
      throw new Error(`chain ${chainId} asset ${symbol} has an invalid address`);
    }
    return { symbol, address };
  });

  return { chainId, name, nativeSymbol, assets };
}

function resolveAsset(chain, requestedAsset) {
  const requested = normalize(requestedAsset);
  if (requested === normalize(chain.nativeSymbol)) {
    return {
      kind: "native",
      symbol: chain.nativeSymbol,
      argument: "ETH",
    };
  }

  const matches = chain.assets.filter((asset) =>
    requested === normalize(asset.symbol) ||
    requestedAsset.toLowerCase() === asset.address.toLowerCase()
  );
  if (matches.length === 0) {
    const available = [
      chain.nativeSymbol,
      ...chain.assets.map((asset) => asset.symbol),
    ].join(", ");
    throw new Error(
      `asset ${requestedAsset} is not configured on ${chain.name}; ` +
      `available assets: ${available}`,
    );
  }
  if (matches.length > 1) {
    throw new Error(
      `asset ${requestedAsset} matches multiple assets on ${chain.name}`,
    );
  }
  const asset = matches[0];
  return {
    kind: "erc20",
    symbol: asset.symbol,
    tokenAddress: asset.address,
    argument: asset.address,
  };
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalize(value) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function parseArguments(args) {
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const option = args[index];
    const value = args[index + 1];
    if (value === undefined) {
      throw new Error(`missing value for ${option ?? "argument"}`);
    }
    switch (option) {
      case "--amount":
        options.amount = value;
        break;
      case "--asset":
        options.asset = value;
        break;
      case "--chain":
        options.chain = value;
        break;
      case "--recipient":
        options.recipient = value;
        break;
      case "--path":
        options.derivationPath = value;
        break;
      case "--config":
        options.configPath = value;
        break;
      default:
        throw new Error(`unknown option ${option}`);
    }
  }

  for (const key of ["amount", "asset", "chain", "recipient"]) {
    if (typeof options[key] !== "string") {
      throw new Error(`missing required option --${key}`);
    }
  }
  return options;
}

async function main() {
  try {
    const result = await resolveTransfer(parseArguments(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`resolve-transfer: ${message}\n`);
    process.exitCode = 1;
  }
}

const entryPoint = process.argv[1] === undefined
  ? undefined
  : pathToFileURL(resolve(process.argv[1])).href;
if (entryPoint === import.meta.url) {
  await main();
}
