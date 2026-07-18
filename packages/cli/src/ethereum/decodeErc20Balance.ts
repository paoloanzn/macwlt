import { decodeFunctionResult } from "viem";
import type { Hex } from "./EvmCall";
import { err, ok, type Result } from "../result";

const balanceOfAbi = [{
  type: "function",
  name: "balanceOf",
  stateMutability: "view",
  inputs: [{ name: "account", type: "address" }],
  outputs: [{ name: "", type: "uint256" }],
}] as const;

export type Erc20BalanceError = {
  readonly kind: "invalid-token-balance";
  readonly message: string;
};

export function decodeErc20Balance(
  data: Hex,
): Result<bigint, Erc20BalanceError> {
  try {
    return ok(decodeFunctionResult({
      abi: balanceOfAbi,
      functionName: "balanceOf",
      data,
    }));
  } catch (caught: unknown) {
    return err({
      kind: "invalid-token-balance",
      message: caught instanceof Error ? caught.message : String(caught),
    });
  }
}
