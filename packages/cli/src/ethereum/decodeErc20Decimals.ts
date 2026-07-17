import { decodeFunctionResult } from "viem";
import { err, ok, type Result } from "../result";
import type { Hex } from "./EvmCall";

const decimalsAbi = [{
  type: "function",
  name: "decimals",
  stateMutability: "view",
  inputs: [],
  outputs: [{ name: "", type: "uint8" }],
}] as const;

export type Erc20DecimalsError = {
  readonly kind: "invalid-token-decimals";
  readonly message: string;
};

export function decodeErc20Decimals(
  data: Hex,
): Result<number, Erc20DecimalsError> {
  try {
    const decimals = decodeFunctionResult({
      abi: decimalsAbi,
      functionName: "decimals",
      data,
    });
    if (!Number.isSafeInteger(decimals) || decimals < 0 || decimals > 255) {
      return err({
        kind: "invalid-token-decimals",
        message: "token returned decimals outside the uint8 range",
      });
    }
    return ok(decimals);
  } catch (caught: unknown) {
    return err({
      kind: "invalid-token-decimals",
      message: caught instanceof Error ? caught.message : String(caught),
    });
  }
}
