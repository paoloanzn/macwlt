import { serializeTransaction, type Hex } from "viem";
import type { LegacyTransaction } from "./LegacyTransaction";

export function serializeUnsignedTransaction(
  transaction: LegacyTransaction,
): Hex {
  return serializeTransaction(transaction);
}
