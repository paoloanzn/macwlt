import { homedir } from "node:os";
import { createFileIfAbsent } from "./createFileIfAbsent";
import { defaultGlobalConfigContents } from "./defaultGlobalConfigContents";
import { globalConfigPath } from "./globalConfigPath";
import { err, ok, type Result } from "../result";

export type EnsureGlobalConfigOptions = {
  readonly homeDirectory?: string;
  readonly createFile?: typeof createFileIfAbsent;
};

export type EnsureGlobalConfigError = {
  readonly kind: "write-failed";
  readonly path: string;
  readonly cause: unknown;
};

export type EnsureGlobalConfigResult = {
  readonly path: string;
  readonly created: boolean;
};

export async function ensureGlobalConfig(
  options: EnsureGlobalConfigOptions = {},
): Promise<Result<EnsureGlobalConfigResult, EnsureGlobalConfigError>> {
  const path = globalConfigPath(options.homeDirectory ?? homedir());
  const createFile = options.createFile ?? createFileIfAbsent;

  try {
    const creation = await createFile(
      path,
      defaultGlobalConfigContents(),
    );
    return ok({ path, created: creation === "created" });
  } catch (cause: unknown) {
    return err({ kind: "write-failed", path, cause });
  }
}
