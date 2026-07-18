import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ConfigStorage } from "./ConfigStorage";
import { defaultGlobalConfigContents } from "./defaultGlobalConfigContents";
import { ensureGlobalConfig } from "./ensureGlobalConfig";
import { globalConfigPath } from "./globalConfigPath";
import { resetGlobalConfig } from "./resetGlobalConfig";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) =>
      rm(path, { recursive: true, force: true })
    ),
  );
});

describe("resetGlobalConfig", () => {
  test("overwrites an existing config with the packaged default", async () => {
    const homeDirectory = await temporaryHome();
    const path = globalConfigPath(homeDirectory);
    await ensureGlobalConfig({ homeDirectory });
    await writeFile(path, '{"custom":true}\n', "utf8");

    const result = await resetGlobalConfig({ homeDirectory });

    expect(result).toEqual({ ok: true, value: path });
    expect(await readFile(path, "utf8")).toBe(defaultGlobalConfigContents());
  });

  test("models storage failures", async () => {
    const cause = new Error("write denied");
    const storage: ConfigStorage = {
      async read(): Promise<string | undefined> {
        return undefined;
      },
      async write(): Promise<void> {
        throw cause;
      },
    };

    const result = await resetGlobalConfig({
      homeDirectory: "/home/alice",
      storage,
    });

    expect(result).toEqual({
      ok: false,
      error: {
        kind: "write-failed",
        path: "/home/alice/.config/macwlt/config.json",
        cause,
      },
    });
  });
});

async function temporaryHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "macwlt-config-reset-"));
  temporaryDirectories.push(path);
  return path;
}
