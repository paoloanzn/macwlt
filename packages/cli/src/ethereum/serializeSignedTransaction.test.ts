import { describe, expect, test } from "bun:test";
import {
  hexToBytes,
  parseTransaction,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { LegacyTransaction } from "./LegacyTransaction";
import { serializeSignedTransaction } from "./serializeSignedTransaction";

const transaction: LegacyTransaction = {
  type: "legacy",
  chainId: 1,
  nonce: 2,
  gas: 65_000n,
  gasPrice: 1_000_000_000n,
  to: "0x0000000000000000000000000000000000000001",
  value: 0n,
  data: "0xa9059cbb",
};

describe("serializeSignedTransaction", () => {
  test("assembles the native r/s/yParity signature like viem", async () => {
    const account = privateKeyToAccount(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
    );
    const expected = await account.signTransaction(transaction);
    const parsed = parseTransaction(expected);
    if (!parsed.r || !parsed.s || parsed.yParity === undefined) {
      throw new Error("expected a signed transaction");
    }
    const signature = hexToBytes(
      `${parsed.r}${parsed.s.slice(2)}${parsed.yParity === 0 ? "00" : "01"}` as Hex,
    );

    const result = serializeSignedTransaction(transaction, signature);

    expect(result).toEqual({ ok: true, value: expected });
  });

  test("rejects malformed native signatures", () => {
    expect(serializeSignedTransaction(transaction, new Uint8Array(64))).toEqual({
      ok: false,
      error: { kind: "invalid-signature-length", actual: 64 },
    });
    const signature = new Uint8Array(65);
    signature[64] = 2;
    expect(serializeSignedTransaction(transaction, signature)).toEqual({
      ok: false,
      error: { kind: "invalid-signature-parity", actual: 2 },
    });
  });
});
