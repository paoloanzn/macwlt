import {
  EthereumClient,
  type EthereumTransactionError,
} from "./EthereumClient";
import type { EthereumAddress, Hex } from "./EvmCall";
import type { Erc20TransactionSigner } from "./sendErc20Token";
import {
  parseTokenAmount,
  type TokenAmountError,
} from "./parseTokenAmount";
import type { LegacyTransaction } from "./LegacyTransaction";
import {
  serializeSignedTransaction,
  type EthereumSignatureError,
} from "./serializeSignedTransaction";
import { serializeUnsignedTransaction } from "./serializeUnsignedTransaction";
import { hexToBytes } from "../hex";
import { err, ok, type Result } from "../result";

export type SendNativeEthInput = {
  readonly recipient: EthereumAddress;
  readonly amount: string;
};

export type SendNativeEthResult = {
  readonly transactionHash: Hex;
  readonly from: EthereumAddress;
  readonly amountWei: bigint;
  readonly feeWei: bigint;
  readonly balanceWei: bigint;
};

export type SendNativeEthStage =
  | "verify-chain"
  | "get-transaction-count"
  | "get-balance"
  | "estimate-gas"
  | "get-gas-price"
  | "broadcast";

export type SendNativeEthError =
  | {
    readonly kind: "chain-client";
    readonly stage: SendNativeEthStage;
    readonly error: EthereumTransactionError;
  }
  | { readonly kind: "amount"; readonly error: TokenAmountError }
  | {
    readonly kind: "insufficient-funds";
    readonly balanceWei: bigint;
    readonly requiredWei: bigint;
  }
  | { readonly kind: "signing-failed"; readonly message: string }
  | { readonly kind: "invalid-signature"; readonly error: EthereumSignatureError };

export async function sendNativeEth(
  client: EthereumClient,
  signer: Erc20TransactionSigner,
  input: SendNativeEthInput,
): Promise<Result<SendNativeEthResult, SendNativeEthError>> {
  const verified = await client.verifyChain();
  if (!verified.ok) {
    return err({ kind: "chain-client", stage: "verify-chain", error: verified.error });
  }
  const amount = parseTokenAmount(input.amount, 18);
  if (!amount.ok) return err({ kind: "amount", error: amount.error });

  const request = {
    from: signer.address,
    to: input.recipient,
    value: amount.value,
  } as const;
  const [nonce, balance, gas, gasPrice] = await Promise.all([
    client.getTransactionCount(signer.address),
    client.getBalance(signer.address),
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
  if (!balance.ok) {
    return err({ kind: "chain-client", stage: "get-balance", error: balance.error });
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

  const feeWei = gas.value * gasPrice.value;
  const requiredWei = amount.value + feeWei;
  if (balance.value < requiredWei) {
    return err({
      kind: "insufficient-funds",
      balanceWei: balance.value,
      requiredWei,
    });
  }

  const transaction: LegacyTransaction = {
    type: "legacy",
    chainId: client.config.chainId,
    nonce: nonce.value,
    gas: gas.value,
    gasPrice: gasPrice.value,
    to: input.recipient,
    value: amount.value,
    data: "0x",
  };
  const preimage = hexToBytes(serializeUnsignedTransaction(transaction));
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
  const signed = serializeSignedTransaction(transaction, signature.value);
  if (!signed.ok) {
    return err({ kind: "invalid-signature", error: signed.error });
  }
  const transactionHash = await client.sendRawTransaction(signed.value);
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
    amountWei: amount.value,
    feeWei,
    balanceWei: balance.value,
  });
}
