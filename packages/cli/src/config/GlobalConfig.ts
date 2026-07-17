import { homedir } from "node:os";
import type { ConfigStorage } from "./ConfigStorage";
import { fileConfigStorage } from "./fileConfigStorage";
import {
  parseGlobalConfigData,
  type GlobalConfigData,
} from "./parseGlobalConfigData";
import type { GlobalConfigValidationError } from "./GlobalConfigValidationError";
import { parseJsonValue, type JsonValue } from "./parseJsonValue";
import { globalConfigPath } from "./globalConfigPath";
import { err, ok, type Result } from "../result";

export type GlobalConfigLoadOptions = {
  readonly homeDirectory?: string;
  readonly storage?: ConfigStorage;
};

export type GlobalConfigLoadError =
  | { readonly kind: "read-failed"; readonly path: string; readonly cause: unknown }
  | { readonly kind: "invalid-json"; readonly path: string; readonly message: string }
  | (GlobalConfigValidationError & { readonly path: string });

export type GlobalConfigSaveError = {
  readonly kind: "write-failed";
  readonly path: string;
  readonly cause: unknown;
};

export class GlobalConfig {
  readonly #path: string;
  readonly #storage: ConfigStorage;
  #data: GlobalConfigData;
  #dirty = false;

  private constructor(
    path: string,
    storage: ConfigStorage,
    data: GlobalConfigData,
  ) {
    this.#path = path;
    this.#storage = storage;
    this.#data = data;
  }

  static async load(
    options: GlobalConfigLoadOptions = {},
  ): Promise<Result<GlobalConfig, GlobalConfigLoadError>> {
    const path = globalConfigPath(options.homeDirectory ?? homedir());
    const storage = options.storage ?? fileConfigStorage;

    let contents: string | undefined;
    try {
      contents = await storage.read(path);
    } catch (cause: unknown) {
      return err({ kind: "read-failed", path, cause });
    }

    if (contents === undefined) {
      return ok(new GlobalConfig(path, storage, {}));
    }

    let input: unknown;
    try {
      input = JSON.parse(contents) as unknown;
    } catch (caught: unknown) {
      return err({
        kind: "invalid-json",
        path,
        message: caught instanceof Error ? caught.message : String(caught),
      });
    }

    const parsed = parseGlobalConfigData(input);
    if (!parsed.ok) return err({ ...parsed.error, path });
    return ok(new GlobalConfig(path, storage, parsed.value));
  }

  get path(): string {
    return this.#path;
  }

  get dirty(): boolean {
    return this.#dirty;
  }

  get data(): GlobalConfigData {
    return cloneData(this.#data);
  }

  get(key: string): JsonValue | undefined {
    if (!Object.hasOwn(this.#data, key)) return undefined;
    const value = this.#data[key];
    return value === undefined ? undefined : cloneValue(value);
  }

  set(
    key: string,
    input: unknown,
  ): Result<void, GlobalConfigValidationError> {
    if (key.length === 0) {
      return err({ kind: "invalid-config", message: "config key must not be empty" });
    }
    const value = parseJsonValue(input);
    if (!value.ok) return value;

    this.#data = { ...this.#data, [key]: value.value };
    this.#dirty = true;
    return ok(undefined);
  }

  delete(key: string): void {
    if (!Object.hasOwn(this.#data, key)) return;
    const { [key]: removed, ...remaining } = this.#data;
    void removed;
    this.#data = remaining;
    this.#dirty = true;
  }

  replace(
    input: unknown,
  ): Result<void, GlobalConfigValidationError> {
    const data = parseGlobalConfigData(input);
    if (!data.ok) return data;

    this.#data = data.value;
    this.#dirty = true;
    return ok(undefined);
  }

  async save(): Promise<Result<void, GlobalConfigSaveError>> {
    const contents = `${JSON.stringify(this.#data, null, 2)}\n`;
    try {
      await this.#storage.write(this.#path, contents);
    } catch (cause: unknown) {
      return err({ kind: "write-failed", path: this.#path, cause });
    }
    this.#dirty = false;
    return ok(undefined);
  }
}

function cloneData(data: GlobalConfigData): GlobalConfigData {
  return structuredClone(data);
}

function cloneValue(value: JsonValue): JsonValue {
  return structuredClone(value);
}
