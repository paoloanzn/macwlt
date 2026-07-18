import { isAddress } from "viem";
import type { EthereumAddress } from "./EvmCall";
import { err, ok, type Result } from "../result";

export type EthereumAsset =
  | { readonly kind: "native-eth" }
  | { readonly kind: "erc20"; readonly tokenAddress: EthereumAddress };

export function parseEthereumAsset(
  input: string,
): Result<EthereumAsset, "invalid-ethereum-asset"> {
  if (input.toUpperCase() === "ETH") return ok({ kind: "native-eth" });
  if (!isAddress(input)) return err("invalid-ethereum-asset");
  return ok({ kind: "erc20", tokenAddress: input });
}
