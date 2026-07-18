import { formatUnits } from "viem";
import {
  EthereumClient,
  type EthereumCallError,
  type EthereumTransactionError,
} from "./EthereumClient";
import type { EthereumAsset } from "./EthereumAsset";
import type { EthereumAddress } from "./EvmCall";
import {
  decodeErc20Balance,
  type Erc20BalanceError,
} from "./decodeErc20Balance";
import {
  decodeErc20Decimals,
  type Erc20DecimalsError,
} from "./decodeErc20Decimals";
import { encodeErc20BalanceOf } from "./encodeErc20BalanceOf";
import { encodeErc20DecimalsCall } from "./encodeErc20DecimalsCall";
import { err, ok, type Result } from "../result";

export type EthereumAssetBalance =
  | {
    readonly kind: "native-eth";
    readonly address: EthereumAddress;
    readonly balance: string;
    readonly balanceBaseUnits: bigint;
    readonly decimals: 18;
  }
  | {
    readonly kind: "erc20";
    readonly address: EthereumAddress;
    readonly tokenAddress: EthereumAddress;
    readonly balance: string;
    readonly balanceBaseUnits: bigint;
    readonly decimals: number;
  };

export type EthereumBalanceStage =
  | "verify-chain"
  | "get-native-balance"
  | "read-token-balance"
  | "read-token-decimals";

export type EthereumAssetBalanceError =
  | {
    readonly kind: "chain-client";
    readonly stage: EthereumBalanceStage;
    readonly error: EthereumCallError | EthereumTransactionError;
  }
  | { readonly kind: "missing-token-balance" }
  | { readonly kind: "missing-token-decimals" }
  | { readonly kind: "token-balance"; readonly error: Erc20BalanceError }
  | { readonly kind: "token-decimals"; readonly error: Erc20DecimalsError };

export async function getEthereumAssetBalance(
  client: EthereumClient,
  address: EthereumAddress,
  asset: EthereumAsset,
): Promise<Result<EthereumAssetBalance, EthereumAssetBalanceError>> {
  const verified = await client.verifyChain();
  if (!verified.ok) {
    return err({ kind: "chain-client", stage: "verify-chain", error: verified.error });
  }

  if (asset.kind === "native-eth") {
    const balance = await client.getBalance(address);
    if (!balance.ok) {
      return err({
        kind: "chain-client",
        stage: "get-native-balance",
        error: balance.error,
      });
    }
    return ok({
      kind: "native-eth",
      address,
      balance: formatUnits(balance.value, 18),
      balanceBaseUnits: balance.value,
      decimals: 18,
    });
  }

  const [balanceCall, decimalsCall] = await Promise.all([
    client.call({
      to: asset.tokenAddress,
      data: encodeErc20BalanceOf(address),
    }),
    client.call({
      to: asset.tokenAddress,
      data: encodeErc20DecimalsCall(),
    }),
  ]);
  if (!balanceCall.ok) {
    return err({
      kind: "chain-client",
      stage: "read-token-balance",
      error: balanceCall.error,
    });
  }
  if (!decimalsCall.ok) {
    return err({
      kind: "chain-client",
      stage: "read-token-decimals",
      error: decimalsCall.error,
    });
  }
  if (balanceCall.value.data === undefined) {
    return err({ kind: "missing-token-balance" });
  }
  if (decimalsCall.value.data === undefined) {
    return err({ kind: "missing-token-decimals" });
  }

  const balance = decodeErc20Balance(balanceCall.value.data);
  if (!balance.ok) return err({ kind: "token-balance", error: balance.error });
  const decimals = decodeErc20Decimals(decimalsCall.value.data);
  if (!decimals.ok) return err({ kind: "token-decimals", error: decimals.error });
  return ok({
    kind: "erc20",
    address,
    tokenAddress: asset.tokenAddress,
    balance: formatUnits(balance.value, decimals.value),
    balanceBaseUnits: balance.value,
    decimals: decimals.value,
  });
}
