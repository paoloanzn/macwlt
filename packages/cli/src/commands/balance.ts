import type { Command, CommandContext } from "../command";
import { GlobalConfig, type GlobalConfigLoadError } from "../config";
import {
  EthereumClient,
  createViemTransport,
  getEthereumAssetBalance,
  getEthereumPortfolioBalances,
  parseEthereumAsset,
  parseEthereumConfig,
  parseEthereumPortfolioConfig,
  type EthereumAsset,
  type EthereumAssetBalanceError,
  type EthereumClientCreationError,
  type EthereumPortfolioAssetBalance,
  type EthereumPortfolioChainBalances,
} from "../ethereum";
import { parseFlags } from "../parseFlags";
import { err, ok, type Result } from "../result";
import { ethereumWalletAddress } from "./ethereumWalletAddress";
import { formatEthereumClientError } from "./formatEthereumClientError";
import { resolveEthereumCommandRpcUrl } from "./resolveEthereumCommandRpcUrl";

export type BalanceArgs =
  | {
    readonly kind: "portfolio";
    readonly derivationPath: string;
    readonly json: boolean;
  }
  | {
    readonly kind: "asset";
    readonly asset: EthereumAsset;
    readonly chainId: number;
    readonly rpcUrl: string | undefined;
    readonly derivationPath: string;
    readonly json: boolean;
  };

type AssetBalanceArgs = Extract<BalanceArgs, { readonly kind: "asset" }>;
type PortfolioBalanceArgs = Extract<BalanceArgs, { readonly kind: "portfolio" }>;

export const balanceCommand: Command<BalanceArgs> = {
  name: "balance",
  describe(): string {
    return [
      "  macwlt balance [--path <derivation-path>] [--json]",
      "  macwlt balance <ETH|token-address> <chain-id> [--rpc <url>] [--path <derivation-path>] [--json]",
    ].join("\n");
  },
  parse: parseBalance,
  async run(
    ctx: CommandContext,
    args: BalanceArgs,
  ): Promise<Result<string, string>> {
    switch (args.kind) {
      case "portfolio":
        return await runPortfolioBalance(ctx, args);
      case "asset":
        return await runAssetBalance(ctx, args);
    }
  },
};

export function parseBalance(
  args: readonly string[],
): Result<BalanceArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.switches.size > 0) {
    return err("balance does not accept switch options");
  }
  for (const option of flags.value.options.keys()) {
    if (option !== "rpc" && option !== "path") {
      return err(`unknown balance option: --${option}`);
    }
  }

  const derivationPath = flags.value.options.get("path") ?? "m";
  if (flags.value.positionals.length === 0) {
    if (flags.value.options.has("rpc")) {
      return err("balance --rpc requires <ETH|token-address> <chain-id>");
    }
    return ok({
      kind: "portfolio",
      derivationPath,
      json: flags.value.json,
    });
  }
  if (flags.value.positionals.length !== 2) {
    return err("balance accepts no positionals or requires <ETH|token-address> <chain-id>");
  }

  const [assetValue, chainIdValue] = flags.value.positionals;
  if (!assetValue) {
    return err("balance asset must be ETH or a valid Ethereum token address");
  }
  const asset = parseEthereumAsset(assetValue);
  if (!asset.ok) {
    return err("balance asset must be ETH or a valid Ethereum token address");
  }
  const chainId = Number(chainIdValue);
  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    return err("balance chain-id must be a positive integer");
  }

  const rpcUrl = flags.value.options.get("rpc");
  if (rpcUrl !== undefined) {
    const config = parseEthereumConfig({ rpcUrl, chainId });
    if (!config.ok) return err("balance --rpc must be a valid HTTP(S) URL");
  }
  return ok({
    kind: "asset",
    asset: asset.value,
    chainId,
    rpcUrl,
    derivationPath,
    json: flags.value.json,
  });
}

async function runAssetBalance(
  ctx: CommandContext,
  args: AssetBalanceArgs,
): Promise<Result<string, string>> {
  const rpcUrl = await resolveEthereumCommandRpcUrl(
    ctx.env,
    args.chainId,
    args.rpcUrl,
  );
  if (!rpcUrl.ok) return rpcUrl;
  const client = EthereumClient.create(
    { rpcUrl: rpcUrl.value, chainId: args.chainId },
    createViemTransport,
  );
  if (!client.ok) {
    return err(`invalid Ethereum client configuration: ${client.error.kind}`);
  }
  const address = ethereumWalletAddress(ctx.client, args.derivationPath);
  if (!address.ok) return address;

  const balance = await getEthereumAssetBalance(
    client.value,
    address.value,
    args.asset,
  );
  if (!balance.ok) return err(formatBalanceError(balance.error));
  if (!args.json) {
    return ok(
      balance.value.kind === "native-eth"
        ? `${balance.value.balance} ETH`
        : balance.value.balance,
    );
  }
  if (balance.value.kind === "native-eth") {
    return ok(JSON.stringify({
      address: balance.value.address,
      chainId: args.chainId,
      asset: "ETH",
      balance: balance.value.balance,
      balanceWei: balance.value.balanceBaseUnits.toString(),
      decimals: balance.value.decimals,
    }, null, 2));
  }
  return ok(JSON.stringify({
    address: balance.value.address,
    chainId: args.chainId,
    tokenAddress: balance.value.tokenAddress,
    balance: balance.value.balance,
    balanceBaseUnits: balance.value.balanceBaseUnits.toString(),
    decimals: balance.value.decimals,
  }, null, 2));
}

async function runPortfolioBalance(
  ctx: CommandContext,
  args: PortfolioBalanceArgs,
): Promise<Result<string, string>> {
  const homeDirectory = ctx.env.HOME?.length ? ctx.env.HOME : undefined;
  const loaded = await GlobalConfig.load({
    homeDirectory,
    storage: ctx.configStorage,
  });
  if (!loaded.ok) return err(formatConfigLoadError(loaded.error));
  const config = parseEthereumPortfolioConfig(loaded.value.data);
  if (!config.ok) {
    return err(`invalid EVM portfolio config ${loaded.value.path}: ${config.error.message}`);
  }
  if (config.value.length === 0) {
    return err(`no EVM chains configured in ${loaded.value.path}`);
  }

  const address = ethereumWalletAddress(ctx.client, args.derivationPath);
  if (!address.ok) return address;
  const portfolio = await getEthereumPortfolioBalances(
    config.value,
    address.value,
    createViemTransport,
  );

  return ok(
    args.json
      ? formatPortfolioJson(address.value, portfolio)
      : formatPortfolioText(address.value, portfolio),
  );
}

function formatPortfolioJson(
  address: string,
  portfolio: readonly EthereumPortfolioChainBalances[],
): string {
  return JSON.stringify({
    address,
    chains: portfolio.map((chain) => {
      if (chain.status === "failed") {
        return {
          chainId: chain.chain.chainId,
          name: chain.chain.name,
          status: "failed",
          error: formatClientCreationError(chain.error),
        };
      }
      return {
        chainId: chain.chain.chainId,
        name: chain.chain.name,
        status: "ok",
        assets: chain.assets
          .filter(isHeldAsset)
          .map(formatPortfolioAssetJson),
        errors: chain.assets
          .filter(isFailedAsset)
          .map((asset) => ({
            symbol: asset.symbol,
            kind: asset.asset.kind === "native-eth" ? "native" : "erc20",
            ...(asset.asset.kind === "erc20"
              ? { tokenAddress: asset.asset.tokenAddress }
              : {}),
            error: formatBalanceError(asset.error),
          })),
      };
    }),
  }, null, 2);
}

function formatPortfolioText(
  address: string,
  portfolio: readonly EthereumPortfolioChainBalances[],
): string {
  const lines = [`Wallet ${address}`];
  let heldAssetCount = 0;

  for (const chain of portfolio) {
    if (chain.status === "failed") {
      lines.push(
        `${chain.chain.name} (${chain.chain.chainId}): unavailable: ${formatClientCreationError(chain.error)}`,
      );
      continue;
    }
    const heldAssets = chain.assets.filter(isHeldAsset);
    const failedAssets = chain.assets.filter(isFailedAsset);
    if (heldAssets.length === 0 && failedAssets.length === 0) continue;

    lines.push(`${chain.chain.name} (${chain.chain.chainId})`);
    for (const asset of heldAssets) {
      heldAssetCount++;
      lines.push(`  ${asset.symbol}: ${asset.balance.balance}`);
    }
    for (const asset of failedAssets) {
      lines.push(`  ${asset.symbol}: unavailable: ${formatBalanceError(asset.error)}`);
    }
  }

  if (heldAssetCount === 0) lines.push("No configured assets held.");
  return lines.join("\n");
}

function formatPortfolioAssetJson(
  asset: Extract<EthereumPortfolioAssetBalance, { readonly status: "fulfilled" }>,
): object {
  const balance = asset.balance;
  return {
    symbol: asset.symbol,
    kind: balance.kind === "native-eth" ? "native" : "erc20",
    ...(balance.kind === "erc20" ? { tokenAddress: balance.tokenAddress } : {}),
    balance: balance.balance,
    balanceBaseUnits: balance.balanceBaseUnits.toString(),
    decimals: balance.decimals,
  };
}

function isHeldAsset(
  asset: EthereumPortfolioAssetBalance,
): asset is Extract<EthereumPortfolioAssetBalance, { readonly status: "fulfilled" }> {
  return asset.status === "fulfilled" && asset.balance.balanceBaseUnits > 0n;
}

function isFailedAsset(
  asset: EthereumPortfolioAssetBalance,
): asset is Extract<EthereumPortfolioAssetBalance, { readonly status: "failed" }> {
  return asset.status === "failed";
}

function formatBalanceError(error: EthereumAssetBalanceError): string {
  switch (error.kind) {
    case "chain-client":
      return `${error.stage} failed: ${formatEthereumClientError(error.error)}`;
    case "missing-token-balance":
      return "token balance call returned no data";
    case "missing-token-decimals":
      return "token decimals call returned no data";
    case "token-balance":
      return `invalid token balance response: ${error.error.message}`;
    case "token-decimals":
      return `invalid token decimals response: ${error.error.message}`;
  }
}

function formatClientCreationError(error: EthereumClientCreationError): string {
  switch (error.kind) {
    case "invalid-rpc-url":
      return `invalid RPC URL ${error.value}`;
    case "invalid-chain-id":
      return `invalid chain ID ${error.value}`;
    case "transport-creation-failed":
      return messageFromUnknown(error.cause);
  }
}

function formatConfigLoadError(error: GlobalConfigLoadError): string {
  switch (error.kind) {
    case "read-failed":
      return `failed to read global config ${error.path}: ${messageFromUnknown(error.cause)}`;
    case "invalid-json":
      return `invalid JSON in global config ${error.path}: ${error.message}`;
    case "invalid-config":
      return `invalid global config ${error.path}: ${error.message}`;
  }
}

function messageFromUnknown(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
