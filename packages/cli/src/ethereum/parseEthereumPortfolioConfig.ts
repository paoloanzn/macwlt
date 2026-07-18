import { isAddress } from "viem";
import { z } from "zod";
import type { GlobalConfigData } from "../config";
import { err, ok, type Result } from "../result";
import { parseEthereumConfig, type RpcUrl } from "./EthereumConfig";
import type { EthereumAddress } from "./EvmCall";

export type ConfiguredErc20Asset = {
  readonly symbol: string;
  readonly address: EthereumAddress;
};

export type ConfiguredEthereumChain = {
  readonly chainId: number;
  readonly name: string;
  readonly rpcUrl: RpcUrl;
  readonly nativeSymbol: string;
  readonly assets: readonly ConfiguredErc20Asset[];
};

export type EthereumPortfolioConfigError = {
  readonly kind: "invalid-portfolio-config";
  readonly message: string;
};

const symbolSchema = z.string().trim().min(1).max(16).regex(/^[A-Za-z0-9._-]+$/);
const assetSchema = z.object({
  symbol: symbolSchema,
  address: z.string().refine(isAddress, "invalid Ethereum address"),
}).strict();
const chainSchema = z.object({
  name: z.string().trim().min(1),
  rpcUrl: z.string(),
  nativeAsset: z.object({
    symbol: symbolSchema,
  }).strict(),
  assets: z.array(assetSchema),
}).strict();
const portfolioSchema = z.object({
  ethereum: z.object({
    chains: z.record(chainSchema),
  }).passthrough(),
}).passthrough();

export function parseEthereumPortfolioConfig(
  input: GlobalConfigData,
): Result<readonly ConfiguredEthereumChain[], EthereumPortfolioConfigError> {
  const parsed = portfolioSchema.safeParse(input);
  if (!parsed.success) {
    return err({
      kind: "invalid-portfolio-config",
      message: parsed.error.issues
        .map((issue) => `${issue.path.join(".") || "config"}: ${issue.message}`)
        .join("; "),
    });
  }

  const chains: ConfiguredEthereumChain[] = [];
  for (const [chainIdValue, chain] of Object.entries(parsed.data.ethereum.chains)) {
    const chainId = Number(chainIdValue);
    if (!Number.isSafeInteger(chainId) || chainId <= 0) {
      return invalid(`ethereum.chains.${chainIdValue}: invalid chain ID`);
    }
    const ethereumConfig = parseEthereumConfig({
      chainId,
      rpcUrl: chain.rpcUrl,
    });
    if (!ethereumConfig.ok) {
      return invalid(`ethereum.chains.${chainIdValue}.rpcUrl: invalid HTTP(S) URL`);
    }

    const symbols = new Set<string>();
    const addresses = new Set<string>();
    for (const asset of chain.assets) {
      const symbol = asset.symbol.toUpperCase();
      const address = asset.address.toLowerCase();
      if (symbol === chain.nativeAsset.symbol.toUpperCase()) {
        return invalid(
          `ethereum.chains.${chainIdValue}.assets: ${asset.symbol} duplicates the native symbol`,
        );
      }
      if (symbols.has(symbol)) {
        return invalid(
          `ethereum.chains.${chainIdValue}.assets: duplicate symbol ${asset.symbol}`,
        );
      }
      if (addresses.has(address)) {
        return invalid(
          `ethereum.chains.${chainIdValue}.assets: duplicate address ${asset.address}`,
        );
      }
      symbols.add(symbol);
      addresses.add(address);
    }

    chains.push({
      chainId,
      name: chain.name,
      rpcUrl: ethereumConfig.value.rpcUrl,
      nativeSymbol: chain.nativeAsset.symbol,
      assets: chain.assets.map((asset) => ({
        symbol: asset.symbol,
        address: asset.address as EthereumAddress,
      })),
    });
  }
  return ok(chains);
}

function invalid(
  message: string,
): Result<never, EthereumPortfolioConfigError> {
  return err({ kind: "invalid-portfolio-config", message });
}
