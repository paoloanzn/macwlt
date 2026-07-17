import { z } from "zod";
import type { GlobalConfigValidationError } from "./GlobalConfigValidationError";
import { parseJsonValue, type JsonValue } from "./parseJsonValue";
import { err, ok, type Result } from "../result";

export type GlobalConfigData = {
  readonly [key: string]: JsonValue;
};

const globalConfigDataSchema = z.record(z.unknown());

export function parseGlobalConfigData(
  input: unknown,
): Result<GlobalConfigData, GlobalConfigValidationError> {
  const parsed = globalConfigDataSchema.safeParse(input);
  if (!parsed.success) {
    return err({
      kind: "invalid-config",
      message: parsed.error.issues
        .map((issue) => `${issue.path.join(".") || "config"}: ${issue.message}`)
        .join("; "),
    });
  }
  const data: Record<string, JsonValue> = {};
  for (const [key, inputValue] of Object.entries(parsed.data)) {
    const value = parseJsonValue(inputValue);
    if (!value.ok) {
      return err({
        kind: "invalid-config",
        message: `${key}: ${value.error.message}`,
      });
    }
    data[key] = value.value;
  }
  return ok(data);
}
