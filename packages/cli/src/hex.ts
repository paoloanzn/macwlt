import { err, ok, type Result } from "./result";

export type HexError =
  | { readonly kind: "empty" }
  | { readonly kind: "invalid"; readonly value: string };

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(input: string): Result<Uint8Array, HexError> {
  const normalized = input.startsWith("0x") || input.startsWith("0X")
    ? input.slice(2)
    : input;
  if (normalized.length === 0) return err({ kind: "empty" });
  if (normalized.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(normalized)) {
    return err({ kind: "invalid", value: input });
  }

  const bytes = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < bytes.length; index++) {
    const pair = normalized.slice(index * 2, index * 2 + 2);
    bytes[index] = Number.parseInt(pair, 16);
  }
  return ok(bytes);
}
