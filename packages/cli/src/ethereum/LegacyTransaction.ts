import type { EthereumAddress, Hex } from "./EvmCall";

export type LegacyTransaction = {
  readonly type: "legacy";
  readonly chainId: number;
  readonly nonce: number;
  readonly gas: bigint;
  readonly gasPrice: bigint;
  readonly to: EthereumAddress;
  readonly value: bigint;
  readonly data: Hex;
};
