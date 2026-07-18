import type { Command, CommandContext } from "../command";
import {
  EthereumClient,
  createViemTransport,
  getEthereumAssetBalance,
  parseEthereumAsset,
  parseEthereumConfig,
  type EthereumAsset,
  type EthereumAssetBalanceError,
} from "../ethereum";
import { err, ok, type Result } from "../result";
import { ethereumWalletAddress } from "./ethereumWalletAddress";
import { formatEthereumClientError } from "./formatEthereumClientError";
import { resolveEthereumCommandRpcUrl } from "./resolveEthereumCommandRpcUrl";
import { parseFlags } from "../parseFlags";

export type BalanceArgs = {
  readonly asset: EthereumAsset;
  readonly chainId: number;
  readonly rpcUrl: string | undefined;
  readonly derivationPath: string;
  readonly json: boolean;
};

export const balanceCommand: Command<BalanceArgs> = {
  name: "balance",
  describe(): string {
    return "  macwlt balance <ETH|token-address> <chain-id> [--rpc <url>] [--path <derivation-path>] [--json]";
  },
  parse: parseBalance,
  async run(
    ctx: CommandContext,
    args: BalanceArgs,
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
  },
};

export function parseBalance(
  args: readonly string[],
): Result<BalanceArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length !== 2) {
    return err("balance requires <ETH|token-address> <chain-id>");
  }
  if (flags.value.switches.size > 0) {
    return err("balance does not accept switch options");
  }
  for (const option of flags.value.options.keys()) {
    if (option !== "rpc" && option !== "path") {
      return err(`unknown balance option: --${option}`);
    }
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
    asset: asset.value,
    chainId,
    rpcUrl,
    derivationPath: flags.value.options.get("path") ?? "m",
    json: flags.value.json,
  });
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
