import { z } from "zod";
import { err, ok, type Result } from "../result";

export type ChainId = number & { readonly __brand: "ChainId" };
export type RpcUrl = string & { readonly __brand: "RpcUrl" };

export type EthereumConfig = {
  readonly rpcUrl: RpcUrl;
  readonly chainId: ChainId;
};

export type EthereumConfigInput = {
  readonly rpcUrl: string;
  readonly chainId: number;
};

export type EthereumConfigError =
  | { readonly kind: "invalid-rpc-url"; readonly value: string }
  | { readonly kind: "invalid-chain-id"; readonly value: number };

const rpcUrlSchema = z
  .string()
  .superRefine((value, context) => {
    try {
      const protocol = new URL(value).protocol;
      if (protocol === "http:" || protocol === "https:") return;
    } catch {
      // Report malformed URLs through the same stable domain error.
    }
    context.addIssue({ code: z.ZodIssueCode.custom, message: "Invalid RPC URL" });
  });

const chainIdSchema = z.number().int().positive().safe();

export function parseEthereumConfig(
  input: EthereumConfigInput,
): Result<EthereumConfig, EthereumConfigError> {
  const rpcUrl = rpcUrlSchema.safeParse(input.rpcUrl);
  if (!rpcUrl.success) {
    return err({ kind: "invalid-rpc-url", value: input.rpcUrl });
  }

  const chainId = chainIdSchema.safeParse(input.chainId);
  if (!chainId.success) {
    return err({ kind: "invalid-chain-id", value: input.chainId });
  }

  return ok({
    rpcUrl: rpcUrl.data as RpcUrl,
    chainId: chainId.data as ChainId,
  });
}
