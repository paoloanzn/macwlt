import { z } from "zod";
import { err, ok, type Result } from "../result";

export type Hex = `0x${string}`;
export type EthereumAddress = `0x${string}`;
export type EvmBlockTag = "earliest" | "finalized" | "latest" | "pending" | "safe";
export type EvmBlock = EvmBlockTag | bigint;

export type EvmCallRequest = {
  readonly to: EthereumAddress;
  readonly data?: Hex;
  readonly from?: EthereumAddress;
  readonly gas?: bigint;
  readonly gasPrice?: bigint;
  readonly value?: bigint;
  readonly block?: EvmBlock;
};

export type EvmCallResult = {
  readonly data: Hex | undefined;
};

export type EvmValidationError = {
  readonly message: string;
};

const addressSchema = z.string().regex(/^0x[0-9a-fA-F]{40}$/);
const hexSchema = z.string().regex(/^0x(?:[0-9a-fA-F]{2})*$/);
const quantitySchema = z.bigint().nonnegative();
const blockSchema = z.union([
  z.enum(["earliest", "finalized", "latest", "pending", "safe"]),
  quantitySchema,
]);

const evmCallRequestSchema = z.object({
  to: addressSchema,
  data: hexSchema.optional(),
  from: addressSchema.optional(),
  gas: quantitySchema.optional(),
  gasPrice: quantitySchema.optional(),
  value: quantitySchema.optional(),
  block: blockSchema.optional(),
}).strict();

const evmCallResultSchema = z.object({
  data: hexSchema.optional(),
});

export function parseEvmCallRequest(
  input: EvmCallRequest,
): Result<EvmCallRequest, EvmValidationError> {
  const parsed = evmCallRequestSchema.safeParse(input);
  if (!parsed.success) {
    return err({ message: parsed.error.issues.map((issue) => issue.message).join("; ") });
  }
  return ok(parsed.data as EvmCallRequest);
}

export function parseEvmCallResult(
  input: unknown,
): Result<EvmCallResult, EvmValidationError> {
  const parsed = evmCallResultSchema.safeParse(input);
  if (!parsed.success) {
    return err({ message: parsed.error.issues.map((issue) => issue.message).join("; ") });
  }
  return ok(parsed.data as EvmCallResult);
}
