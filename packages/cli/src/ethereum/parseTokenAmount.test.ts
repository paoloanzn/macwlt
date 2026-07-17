import { describe, expect, test } from "bun:test";
import { parseTokenAmount } from "./parseTokenAmount";

describe("parseTokenAmount", () => {
  test("converts a decimal token amount to base units", () => {
    expect(parseTokenAmount("1.25", 6)).toEqual({
      ok: true,
      value: 1_250_000n,
    });
  });

  test("rejects zero and precision that would require rounding", () => {
    expect(parseTokenAmount("0.0", 18)).toEqual({
      ok: false,
      error: { kind: "zero-token-amount" },
    });
    expect(parseTokenAmount("1.001", 2)).toEqual({
      ok: false,
      error: { kind: "invalid-token-amount", value: "1.001" },
    });
  });

  test("rejects values outside ERC-20 numeric bounds", () => {
    const overUint256 = (1n << 256n).toString();
    expect(parseTokenAmount(overUint256, 0)).toEqual({
      ok: false,
      error: { kind: "invalid-token-amount", value: overUint256 },
    });
    expect(parseTokenAmount("1", 256)).toEqual({
      ok: false,
      error: { kind: "invalid-token-amount", value: "1" },
    });
  });
});
