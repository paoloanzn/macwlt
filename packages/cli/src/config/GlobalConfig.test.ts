import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { ConfigStorage } from "./ConfigStorage";
import { GlobalConfig } from "./GlobalConfig";
import { globalConfigPath } from "./globalConfigPath";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) =>
      rm(path, { recursive: true, force: true })
    ),
  );
});

describe("GlobalConfig", () => {
  test("loads an empty config when the file does not exist", async () => {
    const homeDirectory = await temporaryHome();

    const result = await GlobalConfig.load({ homeDirectory });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.path).toBe(globalConfigPath(homeDirectory));
    expect(result.value.data).toEqual({});
    expect(result.value.dirty).toBe(false);
  });

  test("writes JSON below ~/.config and reloads it", async () => {
    const homeDirectory = await temporaryHome();
    const loaded = await GlobalConfig.load({ homeDirectory });
    if (!loaded.ok) throw new Error("failed to load test config");

    expect(loaded.value.set("ethereum", {
      rpcUrl: "https://ethereum.example/rpc",
      chainId: 1,
    })).toEqual({ ok: true, value: undefined });
    expect(loaded.value.dirty).toBe(true);

    const saved = await loaded.value.save();

    expect(saved).toEqual({ ok: true, value: undefined });
    expect(loaded.value.dirty).toBe(false);
    const path = globalConfigPath(homeDirectory);
    expect(await readFile(path, "utf8")).toBe(
      [
        "{",
        '  "ethereum": {',
        '    "rpcUrl": "https://ethereum.example/rpc",',
        '    "chainId": 1',
        "  }",
        "}",
        "",
      ].join("\n"),
    );

    const reloaded = await GlobalConfig.load({ homeDirectory });
    expect(reloaded.ok).toBe(true);
    if (!reloaded.ok) return;
    expect(reloaded.value.get("ethereum")).toEqual({
      rpcUrl: "https://ethereum.example/rpc",
      chainId: 1,
    });
  });

  test("rejects invalid JSON loaded from disk", async () => {
    const homeDirectory = await temporaryHome();
    await writeConfig(homeDirectory, "{not json");

    const result = await GlobalConfig.load({ homeDirectory });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error.kind).toBe("invalid-json");
    expect(result.error.path).toBe(globalConfigPath(homeDirectory));
  });

  test("rejects a JSON root that is not an object", async () => {
    const homeDirectory = await temporaryHome();
    await writeConfig(homeDirectory, "[]");

    const result = await GlobalConfig.load({ homeDirectory });

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error.kind).toBe("invalid-config");
  });

  test("rejects non-JSON values without changing existing state", async () => {
    const loaded = await GlobalConfig.load({
      homeDirectory: await temporaryHome(),
    });
    if (!loaded.ok) throw new Error("failed to load test config");
    expect(loaded.value.set("enabled", true).ok).toBe(true);

    const result = loaded.value.set("invalid", 1n);

    expect(result.ok).toBe(false);
    expect(loaded.value.data).toEqual({ enabled: true });
  });

  test("protects state from mutation through input and output objects", async () => {
    const loaded = await GlobalConfig.load({
      homeDirectory: await temporaryHome(),
    });
    if (!loaded.ok) throw new Error("failed to load test config");
    const input = { name: "mainnet" };
    expect(loaded.value.set("network", input).ok).toBe(true);
    input.name = "changed";

    const output = loaded.value.get("network");
    if (!isStringRecord(output)) throw new Error("unexpected test value");
    output.name = "also changed";

    expect(loaded.value.get("network")).toEqual({ name: "mainnet" });
  });

  test("replaces and deletes config entries", async () => {
    const loaded = await GlobalConfig.load({
      homeDirectory: await temporaryHome(),
    });
    if (!loaded.ok) throw new Error("failed to load test config");

    expect(loaded.value.replace({
      network: "mainnet",
      enabled: true,
    }).ok).toBe(true);
    loaded.value.delete("network");

    expect(loaded.value.data).toEqual({ enabled: true });
    expect(loaded.value.get("toString")).toBeUndefined();
  });

  test("models storage read and write failures", async () => {
    const readCause = new Error("read denied");
    const readResult = await GlobalConfig.load({
      homeDirectory: "/home/alice",
      storage: {
        async read(): Promise<string | undefined> {
          throw readCause;
        },
        async write(): Promise<void> {},
      },
    });
    expect(readResult).toEqual({
      ok: false,
      error: {
        kind: "read-failed",
        path: "/home/alice/.config/macwlt/config.json",
        cause: readCause,
      },
    });

    const writeCause = new Error("write denied");
    const storage: ConfigStorage = {
      async read(): Promise<string | undefined> {
        return undefined;
      },
      async write(): Promise<void> {
        throw writeCause;
      },
    };
    const loaded = await GlobalConfig.load({
      homeDirectory: "/home/alice",
      storage,
    });
    if (!loaded.ok) throw new Error("failed to load test config");
    expect(loaded.value.set("enabled", true).ok).toBe(true);

    const writeResult = await loaded.value.save();

    expect(writeResult).toEqual({
      ok: false,
      error: {
        kind: "write-failed",
        path: "/home/alice/.config/macwlt/config.json",
        cause: writeCause,
      },
    });
    expect(loaded.value.dirty).toBe(true);
  });
});

async function temporaryHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "macwlt-config-"));
  temporaryDirectories.push(path);
  return path;
}

async function writeConfig(
  homeDirectory: string,
  contents: string,
): Promise<void> {
  const path = globalConfigPath(homeDirectory);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, contents, "utf8");
}

function isStringRecord(
  input: unknown,
): input is Record<string, string> {
  return typeof input === "object" && input !== null && !Array.isArray(input);
}
