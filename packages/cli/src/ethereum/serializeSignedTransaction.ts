import { serializeTransaction, type Hex, type Signature } from "viem";
import { bytesToHex } from "../hex";
import { err, ok, type Result } from "../result";
import type { LegacyTransaction } from "./LegacyTransaction";

export type EthereumSignatureError =
  | { readonly kind: "invalid-signature-length"; readonly actual: number }
  | { readonly kind: "invalid-signature-parity"; readonly actual: number };

export function serializeSignedTransaction(
  transaction: LegacyTransaction,
  signature: Uint8Array,
): Result<Hex, EthereumSignatureError> {
  if (signature.length !== 65) {
    return err({
      kind: "invalid-signature-length",
      actual: signature.length,
    });
  }
  const parity = signature[64];
  if (parity !== 0 && parity !== 1) {
    return err({
      kind: "invalid-signature-parity",
      actual: parity ?? -1,
    });
  }

  const parsedSignature: Signature = {
    r: `0x${bytesToHex(signature.slice(0, 32))}`,
    s: `0x${bytesToHex(signature.slice(32, 64))}`,
    v: 27n + BigInt(parity),
  };
  return ok(serializeTransaction(transaction, parsedSignature));
}
