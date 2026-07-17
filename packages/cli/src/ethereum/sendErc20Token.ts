import type {
  EthereumCallError,
  EthereumTransactionError,
} from "./EthereumClient";
import { EthereumClient } from "./EthereumClient";
import type { EthereumAddress, Hex } from "./EvmCall";
import {
  decodeErc20Decimals,
  type Erc20DecimalsError,
} from "./decodeErc20Decimals";
import { encodeErc20DecimalsCall } from "./encodeErc20DecimalsCall";
import { encodeErc20Transfer } from "./encodeErc20Transfer";
import type { LegacyTransaction } from "./LegacyTransaction";
import {
  parseTokenAmount,
  type TokenAmountError,
} from "./parseTokenAmount";
import {
  serializeSignedTransaction,
  type EthereumSignatureError,
} from "./serializeSignedTransaction";
import { serializeUnsignedTransaction } from "./serializeUnsignedTransaction";
import { hexToBytes } from "../hex";
import { err, ok, type Result } from "../result";

export type Erc20TransactionSigner = {
  readonly address: EthereumAddress;
  sign(transaction: Uint8Array): Result<Uint8Array, string>;
};

export type SendErc20TokenInput = {
  readonly tokenAddress: EthereumAddress;
  readonly recipient: EthereumAddress;
  readonly amount: string;
};

export type SendErc20TokenResult = {
  readonly transactionHash: Hex;
  readonly from: EthereumAddress;
  readonly amountBaseUnits: bigint;
  readonly decimals: number;
};

export type SendErc20Stage =
  | "verify-chain"
  | "read-token-decimals"
  | "get-transaction-count"
  | "estimate-gas"
  | "get-gas-price"
  | "broadcast";

export type SendErc20TokenError =
  | {
    readonly kind: "chain-client";
    readonly stage: SendErc20Stage;
    readonly error: EthereumCallError | EthereumTransactionError;
  }
  | { readonly kind: "missing-token-decimals" }
  | { readonly kind: "token-decimals"; readonly error: Erc20DecimalsError }
  | { readonly kind: "token-amount"; readonly error: TokenAmountError }
  | { readonly kind: "signing-failed"; readonly message: string }
  | { readonly kind: "invalid-signature"; readonly error: EthereumSignatureError };

export async function sendErc20Token(
  client: EthereumClient,
  signer: Erc20TransactionSigner,
  input: SendErc20TokenInput,
): Promise<Result<SendErc20TokenResult, SendErc20TokenError>> {
  const verified = await client.verifyChain();
  if (!verified.ok) {
    return err({ kind: "chain-client", stage: "verify-chain", error: verified.error });
  }

  const decimalsCall = await client.call({
    to: input.tokenAddress,
    data: encodeErc20DecimalsCall(),
  });
  if (!decimalsCall.ok) {
    return err({
      kind: "chain-client",
      stage: "read-token-decimals",
      error: decimalsCall.error,
    });
  }
  if (decimalsCall.value.data === undefined) {
    return err({ kind: "missing-token-decimals" });
  }

  const decimals = decodeErc20Decimals(decimalsCall.value.data);
  if (!decimals.ok) return err({ kind: "token-decimals", error: decimals.error });

  const amount = parseTokenAmount(input.amount, decimals.value);
  if (!amount.ok) return err({ kind: "token-amount", error: amount.error });
  const data = encodeErc20Transfer(input.recipient, amount.value);
  const request = {
    from: signer.address,
    to: input.tokenAddress,
    data,
    value: 0n,
  } as const;

  const [nonce, gas, gasPrice] = await Promise.all([
    client.getTransactionCount(signer.address),
    client.estimateGas(request),
    client.getGasPrice(),
  ]);
  if (!nonce.ok) {
    return err({
      kind: "chain-client",
      stage: "get-transaction-count",
      error: nonce.error,
    });
  }
  if (!gas.ok) {
    return err({ kind: "chain-client", stage: "estimate-gas", error: gas.error });
  }
  if (!gasPrice.ok) {
    return err({
      kind: "chain-client",
      stage: "get-gas-price",
      error: gasPrice.error,
    });
  }

  const transaction: LegacyTransaction = {
    type: "legacy",
    chainId: client.config.chainId,
    nonce: nonce.value,
    gas: gas.value,
    gasPrice: gasPrice.value,
    to: input.tokenAddress,
    value: 0n,
    data,
  };
  const unsignedTransaction = serializeUnsignedTransaction(transaction);
  const preimage = hexToBytes(unsignedTransaction);
  if (!preimage.ok) {
    return err({
      kind: "signing-failed",
      message: "could not serialize the transaction signing preimage",
    });
  }

  const signature = signer.sign(preimage.value);
  if (!signature.ok) {
    return err({ kind: "signing-failed", message: signature.error });
  }
  const signedTransaction = serializeSignedTransaction(
    transaction,
    signature.value,
  );
  if (!signedTransaction.ok) {
    return err({ kind: "invalid-signature", error: signedTransaction.error });
  }

  const transactionHash = await client.sendRawTransaction(
    signedTransaction.value,
  );
  if (!transactionHash.ok) {
    return err({
      kind: "chain-client",
      stage: "broadcast",
      error: transactionHash.error,
    });
  }
  return ok({
    transactionHash: transactionHash.value,
    from: signer.address,
    amountBaseUnits: amount.value,
    decimals: decimals.value,
  });
}
