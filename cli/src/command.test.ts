import { describe, expect, test } from "bun:test";
import { runCli } from "./command";

describe("runCli", () => {
  test("prints help without loading native code", async () => {
    const result = await runCli(["help"], { MACWLT_LIB: "/missing/libmacwlt.dylib" });

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("macwlt create");
    expect(result.stderr).toBe("");
  });

  test("reports a missing native library for wallet commands", async () => {
    const result = await runCli(["create"], { MACWLT_LIB: "/missing/libmacwlt.dylib" });

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("native library not found");
  });
});
