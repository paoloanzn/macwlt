import { homedir } from "node:os";
import type { ConfigStorage } from "./ConfigStorage";
import { defaultGlobalConfigContents } from "./defaultGlobalConfigContents";
import { fileConfigStorage } from "./fileConfigStorage";
import { globalConfigPath } from "./globalConfigPath";
import { err, ok, type Result } from "../result";

export type ResetGlobalConfigOptions = {
  readonly homeDirectory?: string;
  readonly storage?: ConfigStorage;
};

export type ResetGlobalConfigError = {
  readonly kind: "write-failed";
  readonly path: string;
  readonly cause: unknown;
};

export async function resetGlobalConfig(
  options: ResetGlobalConfigOptions = {},
): Promise<Result<string, ResetGlobalConfigError>> {
  const path = globalConfigPath(options.homeDirectory ?? homedir());
  const storage = options.storage ?? fileConfigStorage;

  try {
    await storage.write(path, defaultGlobalConfigContents());
    return ok(path);
  } catch (cause: unknown) {
    return err({ kind: "write-failed", path, cause });
  }
}
