import { z } from "zod";
import { defaultLibraryPath, openNativeClient, type NativeClient, type NativeError } from "./native";
import { formatNativeError } from "./nativeError";
import { err, type Result } from "./result";
import { commands } from "./commands";

function parsedEnv(value: { [key: string]: unknown }): NodeJS.ProcessEnv {
  return value as unknown as NodeJS.ProcessEnv;
}

const cliInputSchema = z.object({
  args: z.array(z.string()),
  env: z.object({ MACWLT_LIB: z.string().optional() }).passthrough(),
});

export const cliVersion = "0.1.0";

export type CliResult = {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
};

export interface Command<P = unknown> {
  readonly name: string;
  readonly aliases?: readonly string[];
  readonly needsClient?: boolean;
  describe(): string;
  parse(args: readonly string[]): Result<P, string>;
  run(ctx: CommandContext, parsed: P): Promise<Result<string, string>>;
}

export interface CommandContext {
  readonly env: NodeJS.ProcessEnv;
  readonly client: NativeClient;
  readonly registry: readonly Command[];
}

export async function runCli(
  args: readonly string[],
  env: NodeJS.ProcessEnv = process.env,
  registry: readonly Command[] = commands,
): Promise<CliResult> {
  const input = cliInputSchema.safeParse({ args: [...args], env });
  if (!input.success) return failure("invalid process input");

  const [name, ...rest] = input.data.args;
  if (!name) return success(helpText(registry));

  const command = registry.find((c) => c.name === name || c.aliases?.includes(name));
  if (!command) return failure(`unknown command: ${name}\n\n${helpText(registry)}`);

  const parsed = command.parse(rest);
  if (!parsed.ok) return failure(parsed.error);

  if (command.needsClient === false) {
    const ctx: CommandContext = { env: parsedEnv(input.data.env), client: neverClient(), registry };
    return await runCommand(command, ctx, parsed.value);
  }

  const clientResult = openNativeClient(defaultLibraryPath(input.data.env.MACWLT_LIB));
  if (!clientResult.ok) return failure(formatNativeError(clientResult.error));

  const client = clientResult.value;
  try {
    const ctx: CommandContext = { env: parsedEnv(input.data.env), client, registry };
    return await runCommand(command, ctx, parsed.value);
  } finally {
    client.close();
  }
}

async function runCommand<P>(command: Command<P>, ctx: CommandContext, parsed: P): Promise<CliResult> {
  const result = await command.run(ctx, parsed);
  if (!result.ok) return failure(result.error);
  return success(result.value);
}

export function helpText(registry: readonly Command[]): string {
  return [
    "Usage:",
    ...registry.map((c) => c.describe()).filter((line) => line.length > 0),
    "",
    "Environment:",
    "  MACWLT_LIB  Path to libmacwlt.dylib (default: ./build/libmacwlt.dylib)",
  ].join("\n");
}

function neverClient(): NativeClient {
  return {
    libraryPath: "",
    close: () => {},
    withWallet: <T, E>(_body: (wallet: never) => Result<T, E>): Result<T, E | NativeError> =>
      err({ kind: "missing-library", libraryPath: "" }) as unknown as Result<T, E | NativeError>,
  };
}

function success(stdout: string): CliResult {
  return { exitCode: 0, stdout: `${stdout}\n`, stderr: "" };
}

function failure(stderr: string): CliResult {
  return { exitCode: 1, stdout: "", stderr: `${stderr}\n` };
}