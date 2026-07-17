import { bytesToBase64 } from "./base64";
import { bytesToHex } from "./hex";

export function formatDataOutput(bytes: Uint8Array, json: boolean, key: string): string {
  const hex = bytesToHex(bytes);
  if (!json) return hex;
  return JSON.stringify({ [key]: hex }, null, 2);
}

export type PsbtTextFormat = "base64" | "hex";

export function formatPsbt(bytes: Uint8Array, format: PsbtTextFormat): string {
  return format === "base64" ? bytesToBase64(bytes) : bytesToHex(bytes);
}