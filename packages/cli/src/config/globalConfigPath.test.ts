import { describe, expect, test } from "bun:test";
import { globalConfigPath } from "./globalConfigPath";

describe("globalConfigPath", () => {
  test("places the config below the user's .config directory", () => {
    expect(globalConfigPath("/Users/alice")).toBe(
      "/Users/alice/.config/macwlt/config.json",
    );
  });
});
