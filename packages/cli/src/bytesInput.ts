import { err, ok, type Result } from "./result";
import { base64ToBytes } from "./base64";
import { hexToBytes } from "./hex";

export type BytesInput =
  | { readonly kind: "hex"; readonly value: string }
  | { readonly kind: "base64"; readonly value: string }
  | { readonly kind: "file"; readonly path: string };

export function parseBytesInput(
  options: ReadonlyMap<string, string>,
  allowed: readonly string[],
): Result<BytesInput, string> {
  const entries = allowed.flatMap((key) => {
    const value = options.get(key);
    return value ? [{ key, value }] : [];
  });
  if (entries.length !== 1) return err(`provide exactly one input option: ${allowed.map((key) => `--${key}`).join(", ")}`);

  const input = entries[0];
  if (!input) return err("missing input");
  if (input.key === "hex") return ok({ kind: "hex", value: input.value });
  if (input.key === "base64") return ok({ kind: "base64", value: input.value });
  return ok({ kind: "file", path: input.value });
}

export async function readInput(input: BytesInput): Promise<Result<Uint8Array, string>> {
  switch (input.kind) {
    case "hex": {
      const decoded = hexToBytes(input.value);
      if (!decoded.ok) return err(decoded.error.kind === "empty" ? "hex input is empty" : `invalid hex input: ${decoded.error.value}`);
      return decoded;
    }
    case "base64": {
      const decoded = base64ToBytes(input.value);
      if (!decoded.ok) return err(decoded.error.kind === "empty" ? "base64 input is empty" : "invalid base64 input");
      return decoded;
    }
    case "file": {
      try {
        return ok(new Uint8Array(await Bun.file(input.path).arrayBuffer()));
      } catch (caught: unknown) {
        return err(`failed to read ${input.path}: ${caught instanceof Error ? caught.message : String(caught)}`);
      }
    }
  }
}