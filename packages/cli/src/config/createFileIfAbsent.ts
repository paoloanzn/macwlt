import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export async function createFileIfAbsent(
  path: string,
  contents: string,
): Promise<"created" | "already-exists"> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  try {
    await writeFile(path, contents, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    return "created";
  } catch (caught: unknown) {
    if (isAlreadyExistsError(caught)) return "already-exists";
    throw caught;
  }
}

function isAlreadyExistsError(caught: unknown): boolean {
  return caught instanceof Error
    && "code" in caught
    && caught.code === "EEXIST";
}
