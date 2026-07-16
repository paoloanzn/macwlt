import { err, ok, type Result } from "./result";

export type Base64Error =
  | { readonly kind: "empty" }
  | { readonly kind: "invalid"; readonly value: string };

export function bytesToBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64");
}

export function base64ToBytes(input: string): Result<Uint8Array, Base64Error> {
  if (input.length === 0) return err({ kind: "empty" });
  const normalized = input.trim();
  if (normalized.length === 0) return err({ kind: "empty" });

  const decoded = Buffer.from(normalized, "base64");
  if (decoded.length === 0 || Buffer.from(decoded).toString("base64").replace(/=+$/, "") !== normalized.replace(/=+$/, "")) {
    return err({ kind: "invalid", value: input });
  }
  return ok(new Uint8Array(decoded));
}
