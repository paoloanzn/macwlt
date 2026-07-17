import type { EthereumAddress, Hex } from "./EvmCall";

export type EvmTransactionRequest = {
  readonly from: EthereumAddress;
  readonly to: EthereumAddress;
  readonly data?: Hex;
  readonly value?: bigint;
};

export type TransactionHash = Hex;
