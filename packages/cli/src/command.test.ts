import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCli, type Command } from "./command";
import {
  defaultGlobalConfigContents,
  ensureGlobalConfig,
  globalConfigPath,
} from "./config";
import { err, ok } from "./result";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) =>
      rm(path, { recursive: true, force: true })
    ),
  );
});

describe("runCli", () => {
  test("prints help without loading native code", async () => {
    const homeDirectory = await temporaryHome();

    const result = await runCli(
      ["help"],
      { HOME: homeDirectory, MACWLT_LIB: "/missing/libmacwlt.dylib" },
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("macwlt create");
    expect(result.stderr).toBe("");
    expect(await readFile(globalConfigPath(homeDirectory), "utf8")).toBe(
      defaultGlobalConfigContents(),
    );
  });

  test("reports a missing native library for wallet commands", async () => {
    const result = await runCli(
      ["create"],
      {
        HOME: await temporaryHome(),
        MACWLT_LIB: "/missing/libmacwlt.dylib",
      },
    );

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("native library not found");
  });

  test("requires an explicit confirmation for reset", async () => {
    const result = await runCli(
      ["reset"],
      {
        HOME: await temporaryHome(),
        MACWLT_LIB: "/missing/libmacwlt.dylib",
      },
    );

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("reset requires --yes");
  });

  test("accepts taproot address types before loading native code", async () => {
    const result = await runCli(
      ["address", "m/86/0/0/0/0", "--type", "bitcoin-taproot"],
      {
        HOME: await temporaryHome(),
        MACWLT_LIB: "/missing/libmacwlt.dylib",
      },
    );

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("native library not found");
    expect(result.stderr).not.toContain("address requires --type");
  });

  test("initializes config before running a command", async () => {
    const homeDirectory = await temporaryHome();
    const probeCommand: Command<{ readonly kind: "probe" }> = {
      name: "probe",
      needsClient: false,
      describe(): string {
        return "";
      },
      parse() {
        return ok({ kind: "probe" as const });
      },
      async run() {
        return ok(await readFile(globalConfigPath(homeDirectory), "utf8"));
      },
    };

    const result = await runCli(
      ["probe"],
      { HOME: homeDirectory },
      [probeCommand],
    );

    expect(result).toEqual({
      exitCode: 0,
      stdout: `${defaultGlobalConfigContents()}\n`,
      stderr: "",
    });
  });

  test("preserves existing config during startup", async () => {
    const homeDirectory = await temporaryHome();
    const path = globalConfigPath(homeDirectory);
    const customContents = '{"custom":true}\n';
    await ensureGlobalConfig({ homeDirectory });
    await writeFile(path, customContents, "utf8");

    const result = await runCli(
      ["help"],
      { HOME: homeDirectory, MACWLT_LIB: "/missing/libmacwlt.dylib" },
    );

    expect(result.exitCode).toBe(0);
    expect(await readFile(path, "utf8")).toBe(customContents);
  });

  test("runs an optional hook before the command body", async () => {
    const events: string[] = [];
    const hookedCommand: Command<{ readonly value: string }> = {
      name: "hooked",
      needsClient: false,
      describe(): string {
        return "";
      },
      parse(args) {
        return ok({ value: args.join(",") });
      },
      beforeRun() {
        events.push("before");
        return ok(undefined);
      },
      async run(_ctx, parsed) {
        events.push(`run:${parsed.value}`);
        return ok("hooked command ran");
      },
    };

    const result = await runCli(
      ["hooked", "parsed"],
      { HOME: await temporaryHome(), HOOK_VALUE: "context" },
      [hookedCommand],
    );

    expect(result.exitCode).toBe(0);
    expect(events).toEqual([
      "before",
      "run:parsed",
    ]);
  });

  test("does not run the command body when its hook fails", async () => {
    let commandRan = false;
    const hookedCommand: Command<{ readonly kind: "hooked" }> = {
      name: "hooked",
      needsClient: false,
      describe(): string {
        return "";
      },
      parse() {
        return ok({ kind: "hooked" as const });
      },
      async beforeRun() {
        return err("before-run failed");
      },
      async run() {
        commandRan = true;
        return ok("unexpected");
      },
    };

    const result = await runCli(
      ["hooked"],
      { HOME: await temporaryHome() },
      [hookedCommand],
    );

    expect(result).toEqual({
      exitCode: 1,
      stdout: "",
      stderr: "before-run failed\n",
    });
    expect(commandRan).toBe(false);
  });
});

async function temporaryHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "macwlt-command-"));
  temporaryDirectories.push(path);
  return path;
}
