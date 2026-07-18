import { describe, expect, test } from "bun:test";
import { createConfirmationHook } from "./createConfirmationHook";

describe("createConfirmationHook", () => {
  test("allows execution after confirmation", async () => {
    let question = "";
    const hook = createConfirmationHook(async (value) => {
      question = value;
      return true;
    });

    expect(await hook()).toEqual({ ok: true, value: undefined });
    expect(question).toBe("Continue? [y/N] ");
  });

  test("cancels execution when confirmation is declined", async () => {
    const hook = createConfirmationHook(async () => false);

    expect(await hook()).toEqual({
      ok: false,
      error: "command cancelled",
    });
  });
});
