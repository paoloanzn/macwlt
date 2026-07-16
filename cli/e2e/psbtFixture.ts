import { createHash } from "node:crypto";
import { hexToBytes } from "../src/hex";

export function psbtForRootPublicKey(publicKeyHex: string): Uint8Array {
  const publicKey = unwrapBytes(hexToBytes(publicKeyHex));
  const publicKeyHash = hash160(publicKey);
  const fingerprint = publicKeyHash.slice(0, 4);
  const scriptPubkey = concatBytes([Uint8Array.of(0x00, 0x14), publicKeyHash]);

  const unsignedTx = concatBytes([
    uint32LE(2),
    compactSize(1),
    new Uint8Array(32),
    uint32LE(0),
    compactSize(0),
    uint32LE(0xffffffff),
    compactSize(1),
    uint64LE(900n),
    compactSize(scriptPubkey.length),
    scriptPubkey,
    uint32LE(0),
  ]);

  const witnessUtxo = concatBytes([
    uint64LE(1000n),
    compactSize(scriptPubkey.length),
    scriptPubkey,
  ]);

  return concatBytes([
    ascii("psbt"),
    Uint8Array.of(0xff),
    psbtPair(Uint8Array.of(0x00), unsignedTx),
    Uint8Array.of(0x00),
    psbtPair(Uint8Array.of(0x01), witnessUtxo),
    psbtPair(concatBytes([Uint8Array.of(0x06), publicKey]), fingerprint),
    Uint8Array.of(0x00),
    Uint8Array.of(0x00),
  ]);
}

function psbtPair(key: Uint8Array, value: Uint8Array): Uint8Array {
  return concatBytes([compactSize(key.length), key, compactSize(value.length), value]);
}

function unwrapBytes(result: ReturnType<typeof hexToBytes>): Uint8Array {
  if (!result.ok) throw new Error(`invalid fixture hex: ${result.error.kind}`);
  return result.value;
}

function hash160(bytes: Uint8Array): Uint8Array {
  const sha256 = createHash("sha256").update(bytes).digest();
  return new Uint8Array(createHash("ripemd160").update(sha256).digest());
}

function ascii(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function compactSize(value: number): Uint8Array {
  if (!Number.isInteger(value) || value < 0 || value > 252) {
    throw new Error(`compact size fixture value out of range: ${value}`);
  }
  return Uint8Array.of(value);
}

function uint32LE(value: number): Uint8Array {
  const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, value, true);
  return bytes;
}

function uint64LE(value: bigint): Uint8Array {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, value, true);
  return bytes;
}

function concatBytes(chunks: readonly Uint8Array[]): Uint8Array {
  const length = chunks.reduce((total, chunk) => total + chunk.length, 0);
  const output = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}
