import { resolve } from "node:path";

export type CliResult = {
  readonly exitCode: number | null;
  readonly stdout: string;
  readonly stderr: string;
};

export const cliRoot = resolve(import.meta.dir, "..");
export const repoRoot = resolve(cliRoot, "..");
export const nativeLibraryPath = resolve(repoRoot, "build/libmacwlt.dylib");

export function runCommand(args: readonly string[]): CliResult {
  const result = Bun.spawnSync({
    cmd: ["bun", "run", "src/main.ts", ...args],
    cwd: cliRoot,
    env: {
      ...process.env,
      MACWLT_LIB: nativeLibraryPath,
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  return {
    exitCode: result.exitCode,
    stdout: new TextDecoder().decode(result.stdout),
    stderr: new TextDecoder().decode(result.stderr),
  };
}
