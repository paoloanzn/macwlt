import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defaultGlobalConfigContents } from "./defaultGlobalConfigContents";
import { ensureGlobalConfig } from "./ensureGlobalConfig";
import { globalConfigPath } from "./globalConfigPath";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) =>
      rm(path, { recursive: true, force: true })
    ),
  );
});

describe("ensureGlobalConfig", () => {
  test("creates the packaged default when config is absent", async () => {
    const homeDirectory = await temporaryHome();

    const result = await ensureGlobalConfig({ homeDirectory });

    expect(result).toEqual({
      ok: true,
      value: {
        path: globalConfigPath(homeDirectory),
        created: true,
      },
    });
    expect(await readFile(globalConfigPath(homeDirectory), "utf8")).toBe(
      defaultGlobalConfigContents(),
    );
  });

  test("does not alter an existing config", async () => {
    const homeDirectory = await temporaryHome();
    const path = globalConfigPath(homeDirectory);
    const customContents = '{"custom":true}\n';
    await ensureGlobalConfig({ homeDirectory });
    await writeFile(path, customContents, "utf8");

    const result = await ensureGlobalConfig({ homeDirectory });

    expect(result).toEqual({
      ok: true,
      value: { path, created: false },
    });
    expect(await readFile(path, "utf8")).toBe(customContents);
  });

  test("creates once across concurrent initializers", async () => {
    const homeDirectory = await temporaryHome();

    const results = await Promise.all(
      Array.from({ length: 8 }, () => ensureGlobalConfig({ homeDirectory })),
    );

    expect(
      results.filter((result) => result.ok && result.value.created),
    ).toHaveLength(1);
    expect(results.every((result) => result.ok)).toBe(true);
    expect(await readFile(globalConfigPath(homeDirectory), "utf8")).toBe(
      defaultGlobalConfigContents(),
    );
  });

  test("models storage failures", async () => {
    const cause = new Error("write denied");

    const result = await ensureGlobalConfig({
      homeDirectory: "/home/alice",
      async createFile(): Promise<"created" | "already-exists"> {
        throw cause;
      },
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
  const path = await mkdtemp(join(tmpdir(), "macwlt-config-ensure-"));
  temporaryDirectories.push(path);
  return path;
}
