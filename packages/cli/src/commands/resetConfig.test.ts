import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runCli, type Command } from "../command";
import { commands } from "../commands";
import {
  defaultGlobalConfigContents,
  ensureGlobalConfig,
  globalConfigPath,
} from "../config";
import { createConfirmationHook } from "../hooks/createConfirmationHook";
import type { ConfirmationPrompt } from "../terminalConfirmationPrompt";
import {
  parseResetConfig,
  resetConfigCommand,
  type ResetConfigArgs,
} from "./resetConfig";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((path) =>
      rm(path, { recursive: true, force: true })
    ),
  );
});

describe("reset-config", () => {
  test("parses its supported output modes", () => {
    expect(parseResetConfig([])).toEqual({
      ok: true,
      value: { json: false },
    });
    expect(parseResetConfig(["--json"])).toEqual({
      ok: true,
      value: { json: true },
    });
  });

  test("rejects unsupported arguments", () => {
    expect(parseResetConfig(["extra"])).toEqual({
      ok: false,
      error: "reset-config does not accept positional arguments",
    });
    expect(parseResetConfig(["--yes"])).toEqual({
      ok: false,
      error: "reset-config only accepts --json",
    });
  });

  test("is registered without requiring the native library", async () => {
    const homeDirectory = await temporaryHome();
    const path = globalConfigPath(homeDirectory);
    await ensureGlobalConfig({ homeDirectory });
    await writeFile(path, '{"custom":true}\n', "utf8");
    let confirmationQuestion = "";
    const command = resetConfigWithPrompt(async (question) => {
      confirmationQuestion = question;
      return true;
    });

    const result = await runCli(
      ["reset-config", "--json"],
      { HOME: homeDirectory, MACWLT_LIB: "/missing/libmacwlt.dylib" },
      [command],
    );

    expect(commands.some((command) => command.name === "reset-config")).toBe(true);
    expect(confirmationQuestion).toBe("Continue? [y/N] ");
    expect(result.exitCode).toBe(0);
    expect(JSON.parse(result.stdout) as unknown).toEqual({
      reset: true,
      path,
    });
    expect(await readFile(path, "utf8")).toBe(defaultGlobalConfigContents());
  });

  test("preserves config when confirmation defaults to no", async () => {
    const homeDirectory = await temporaryHome();
    const path = globalConfigPath(homeDirectory);
    const customContents = '{"custom":true}\n';
    await ensureGlobalConfig({ homeDirectory });
    await writeFile(path, customContents, "utf8");
    const command = resetConfigWithPrompt(async () => false);

    const result = await runCli(
      ["reset-config"],
      { HOME: homeDirectory },
      [command],
    );

    expect(result).toEqual({
      exitCode: 1,
      stdout: "",
      stderr: "command cancelled\n",
    });
    expect(await readFile(path, "utf8")).toBe(customContents);
  });
});

async function temporaryHome(): Promise<string> {
  const path = await mkdtemp(join(tmpdir(), "macwlt-reset-config-command-"));
  temporaryDirectories.push(path);
  return path;
}

function resetConfigWithPrompt(
  prompt: ConfirmationPrompt,
): Command<ResetConfigArgs> {
  return {
    name: resetConfigCommand.name,
    needsClient: resetConfigCommand.needsClient,
    beforeRun: createConfirmationHook(prompt),
    describe(): string {
      return resetConfigCommand.describe();
    },
    parse(args) {
      return resetConfigCommand.parse(args);
    },
    async run(ctx, parsed) {
      return await resetConfigCommand.run(ctx, parsed);
    },
  };
}
