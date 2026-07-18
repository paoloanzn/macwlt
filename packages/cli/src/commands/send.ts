import { isAddress } from "viem";
import type { Command, CommandContext } from "../command";
import { GlobalConfig, type GlobalConfigLoadError } from "../config";
import {
  EthereumClient,
  createViemTransport,
  parseEthereumConfig,
  resolveEthereumRpcUrl,
  sendErc20Token,
  sendNativeEth,
  type Erc20TransactionSigner,
  type EthereumAddress,
  type EthereumCallError,
  type EthereumTransactionError,
  type SendErc20TokenError,
  type SendNativeEthError,
} from "../ethereum";
import { formatNativeError } from "../nativeError";
import { parseFlags } from "../parseFlags";
import { err, ok, type Result } from "../result";
import { runWithWallet } from "../withWallet";

export type SendArgs = {
  readonly amount: string;
  readonly asset:
    | { readonly kind: "native-eth" }
    | { readonly kind: "erc20"; readonly tokenAddress: EthereumAddress };
  readonly chainId: number;
  readonly recipient: EthereumAddress;
  readonly rpcUrl: string | undefined;
  readonly derivationPath: string;
  readonly json: boolean;
};

export const sendCommand: Command<SendArgs> = {
  name: "send",
  describe(): string {
    return "  macwlt send <amount> <token-address|ETH> <chain-id> <recipient> [--rpc <url>] [--path <derivation-path>] [--json]";
  },
  parse: parseSend,
  async run(ctx: CommandContext, args: SendArgs): Promise<Result<string, string>> {
    const rpcUrl = await rpcUrlForCommand(ctx, args);
    if (!rpcUrl.ok) return rpcUrl;

    const ethereumClient = EthereumClient.create(
      { rpcUrl: rpcUrl.value, chainId: args.chainId },
      createViemTransport,
    );
    if (!ethereumClient.ok) {
      return err(`invalid Ethereum client configuration: ${ethereumClient.error.kind}`);
    }

    const signer = ethereumSigner(ctx, args.derivationPath);
    if (!signer.ok) return signer;
    if (args.asset.kind === "native-eth") {
      const sent = await sendNativeEth(ethereumClient.value, signer.value, {
        recipient: args.recipient,
        amount: args.amount,
      });
      if (!sent.ok) return err(formatNativeSendError(sent.error));
      if (!args.json) return ok(sent.value.transactionHash);
      return ok(JSON.stringify({
        transactionHash: sent.value.transactionHash,
        chainId: args.chainId,
        asset: "ETH",
        recipient: args.recipient,
        from: sent.value.from,
        amount: args.amount,
        amountWei: sent.value.amountWei.toString(),
        feeWei: sent.value.feeWei.toString(),
      }, null, 2));
    } else {
      const sent = await sendErc20Token(ethereumClient.value, signer.value, {
        tokenAddress: args.asset.tokenAddress,
        recipient: args.recipient,
        amount: args.amount,
      });
      if (!sent.ok) return err(formatSendError(sent.error));

      if (!args.json) return ok(sent.value.transactionHash);
      return ok(JSON.stringify({
        transactionHash: sent.value.transactionHash,
        chainId: args.chainId,
        tokenAddress: args.asset.tokenAddress,
        recipient: args.recipient,
        from: sent.value.from,
        amount: args.amount,
        amountBaseUnits: sent.value.amountBaseUnits.toString(),
        decimals: sent.value.decimals,
      }, null, 2));
    }
  },
};

export function parseSend(args: readonly string[]): Result<SendArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length !== 4) {
    return err(
      "send requires <amount> <token-address> <chain-id> <recipient>",
    );
  }
  if (flags.value.switches.size > 0) {
    return err("send does not accept switch options");
  }
  for (const option of flags.value.options.keys()) {
    if (option !== "rpc" && option !== "path") {
      return err(`unknown send option: --${option}`);
    }
  }

  const [amount, assetValue, chainIdValue, recipient] =
    flags.value.positionals;
  if (!amount || !/^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(amount)) {
    return err("send amount must be a non-negative decimal number");
  }
  if (/^0(?:\.0+)?$/.test(amount)) {
    return err("send amount must be greater than zero");
  }
  if (!assetValue || (assetValue.toUpperCase() !== "ETH" && !isAddress(assetValue))) {
    return err("send token-address must be ETH or a valid Ethereum address");
  }
  if (!recipient || !isAddress(recipient)) {
    return err("send recipient must be a valid Ethereum address");
  }

  const chainId = Number(chainIdValue);
  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    return err("send chain-id must be a positive integer");
  }

  const rpcUrl = flags.value.options.get("rpc");
  if (rpcUrl !== undefined) {
    const config = parseEthereumConfig({ rpcUrl, chainId });
    if (!config.ok) return err("send --rpc must be a valid HTTP(S) URL");
  }

  return ok({
    amount,
    asset: assetValue.toUpperCase() === "ETH"
      ? { kind: "native-eth" }
      : { kind: "erc20", tokenAddress: assetValue as EthereumAddress },
    chainId,
    recipient,
    rpcUrl,
    derivationPath: flags.value.options.get("path") ?? "m",
    json: flags.value.json,
  });
}

async function rpcUrlForCommand(
  ctx: CommandContext,
  args: SendArgs,
): Promise<Result<string, string>> {
  if (args.rpcUrl !== undefined) return ok(args.rpcUrl);

  const homeDirectory = ctx.env.HOME?.length ? ctx.env.HOME : undefined;
  const loaded = await GlobalConfig.load({ homeDirectory });
  if (!loaded.ok) return err(formatConfigLoadError(loaded.error));
  const rpcUrl = resolveEthereumRpcUrl(loaded.value.data, args.chainId);
  if (!rpcUrl.ok) {
    const configPath = loaded.value.path;
    return err(
      rpcUrl.error.kind === "missing-chain-rpc"
        ? `no RPC configured for chain ${args.chainId} in ${configPath}; set ethereum.chains.${args.chainId}.rpcUrl or pass --rpc`
        : `invalid RPC configured for chain ${args.chainId} in ${configPath}`,
    );
  }
  return ok(rpcUrl.value);
}

function ethereumSigner(
  ctx: CommandContext,
  derivationPath: string,
): Result<Erc20TransactionSigner, string> {
  const address = runWithWallet<string>(ctx.client, (wallet) => {
    const bootstrapped = wallet.bootstrap();
    if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
    const exported = wallet.exportAddress(derivationPath, "ethereum");
    if (!exported.ok) return err(formatNativeError(exported.error));
    return ok(exported.value);
  });
  if (!address.ok) return address;
  if (!isAddress(address.value)) {
    return err("native wallet returned an invalid Ethereum address");
  }

  return ok({
    address: address.value,
    sign(transaction: Uint8Array): Result<Uint8Array, string> {
      return runWithWallet<Uint8Array>(ctx.client, (wallet) => {
        const bootstrapped = wallet.bootstrap();
        if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
        const signature = wallet.signEthereumTransaction(transaction);
        if (!signature.ok) return err(formatNativeError(signature.error));
        return ok(signature.value);
      });
    },
  });
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

function formatSendError(error: SendErc20TokenError): string {
  switch (error.kind) {
    case "chain-client":
      return `${error.stage} failed: ${formatChainClientError(error.error)}`;
    case "missing-token-decimals":
      return "token decimals call returned no data";
    case "token-decimals":
      return `invalid token decimals response: ${error.error.message}`;
    case "token-amount":
      return error.error.kind === "zero-token-amount"
        ? "send amount must be greater than zero"
        : `send amount ${error.error.value} cannot be represented by this token`;
    case "signing-failed":
      return `transaction signing failed: ${error.message}`;
    case "invalid-signature":
      return error.error.kind === "invalid-signature-length"
        ? `native wallet returned a ${error.error.actual}-byte Ethereum signature; expected 65`
        : `native wallet returned invalid Ethereum recovery parity ${error.error.actual}`;
  }
}

function formatNativeSendError(error: SendNativeEthError): string {
  switch (error.kind) {
    case "chain-client":
      return `${error.stage} failed: ${formatChainClientError(error.error)}`;
    case "amount":
      return error.error.kind === "zero-token-amount"
        ? "send amount must be greater than zero"
        : "send ETH amount is invalid";
    case "insufficient-funds":
      return `insufficient ETH balance: have ${error.balanceWei} wei, require ${error.requiredWei} wei including gas`;
    case "signing-failed":
      return `transaction signing failed: ${error.message}`;
    case "invalid-signature":
      return error.error.kind === "invalid-signature-length"
        ? `native wallet returned a ${error.error.actual}-byte Ethereum signature; expected 65`
        : `native wallet returned invalid Ethereum recovery parity ${error.error.actual}`;
  }
}

function formatChainClientError(
  error: EthereumCallError | EthereumTransactionError,
): string {
  switch (error.kind) {
    case "unsupported-transport":
      return "configured Ethereum transport does not support transactions";
    case "invalid-request":
      return error.message;
    case "transport-failed":
      return messageFromUnknown(error.cause);
    case "invalid-response":
      return error.message;
    case "chain-mismatch":
      return `RPC node reports chain ${error.actual}, expected ${error.expected}`;
  }
}

function messageFromUnknown(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
