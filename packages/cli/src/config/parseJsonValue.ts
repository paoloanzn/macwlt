import { z } from "zod";
import type { GlobalConfigValidationError } from "./GlobalConfigValidationError";
import { err, ok, type Result } from "../result";

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

const jsonValueSchema: z.ZodType<JsonValue> = z.lazy(() =>
  z.union([
    z.null(),
    z.boolean(),
    z.number().finite(),
    z.string(),
    z.array(jsonValueSchema),
    z.record(jsonValueSchema),
  ])
);

export function parseJsonValue(
  input: unknown,
): Result<JsonValue, GlobalConfigValidationError> {
  const parsed = jsonValueSchema.safeParse(input);
  if (!parsed.success) {
    return err({
      kind: "invalid-config",
      message: parsed.error.issues
        .map((issue) => `${issue.path.join(".") || "value"}: ${issue.message}`)
        .join("; "),
    });
  }
  return ok(parsed.data);
}
