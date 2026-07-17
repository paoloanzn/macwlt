import { parseUnits } from "viem";
import { err, ok, type Result } from "../result";

export type TokenAmountError =
  | { readonly kind: "invalid-token-amount"; readonly value: string }
  | { readonly kind: "zero-token-amount" };

export function parseTokenAmount(
  value: string,
  decimals: number,
): Result<bigint, TokenAmountError> {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    return err({ kind: "invalid-token-amount", value });
  }
  if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(value)) {
    return err({ kind: "invalid-token-amount", value });
  }
  const fractionalDigits = value.split(".")[1]?.length ?? 0;
  if (fractionalDigits > decimals) {
    return err({ kind: "invalid-token-amount", value });
  }

  try {
    const amount = parseUnits(value, decimals);
    if (amount <= 0n) return err({ kind: "zero-token-amount" });
    if (amount >= 1n << 256n) {
      return err({ kind: "invalid-token-amount", value });
    }
    return ok(amount);
  } catch {
    return err({ kind: "invalid-token-amount", value });
  }
}
