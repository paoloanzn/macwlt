import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { ConfigStorage } from "./ConfigStorage";

export const fileConfigStorage: ConfigStorage = {
  async read(path: string): Promise<string | undefined> {
    try {
      return await readFile(path, "utf8");
    } catch (caught: unknown) {
      if (isNotFoundError(caught)) return undefined;
      throw caught;
    }
  },

  async write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(path), { recursive: true, mode: 0o700 });
    await writeFile(path, contents, { encoding: "utf8", mode: 0o600 });
  },
};

function isNotFoundError(caught: unknown): boolean {
  return caught instanceof Error
    && "code" in caught
    && caught.code === "ENOENT";
}
