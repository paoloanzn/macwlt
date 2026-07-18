import type { Command, CommandContext } from "../command";
import { resetGlobalConfig } from "../config";
import { createConfirmationHook } from "../hooks/createConfirmationHook";
import { parseFlags } from "../parseFlags";
import { err, ok, type Result } from "../result";

export type ResetConfigArgs = { readonly json: boolean };

export const resetConfigCommand: Command<ResetConfigArgs> = {
  name: "reset-config",
  needsClient: false,
  beforeRun: createConfirmationHook(),
  describe(): string {
    return "  macwlt reset-config [--json]";
  },
  parse: parseResetConfig,
  async run(
    ctx: CommandContext,
    args: ResetConfigArgs,
  ): Promise<Result<string, string>> {
    const reset = await resetGlobalConfig({
      homeDirectory: ctx.env.HOME?.length ? ctx.env.HOME : undefined,
      storage: ctx.configStorage,
    });
    if (!reset.ok) {
      return err(
        `failed to reset config ${reset.error.path}: ${messageFromUnknown(reset.error.cause)}`,
      );
    }

    if (!args.json) return ok(`config reset to defaults: ${reset.value}`);
    return ok(JSON.stringify({
      reset: true,
      path: reset.value,
    }, null, 2));
  },
};

export function parseResetConfig(
  args: readonly string[],
): Result<ResetConfigArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) {
    return err("reset-config does not accept positional arguments");
  }
  if (flags.value.options.size > 0 || flags.value.switches.size > 0) {
    return err("reset-config only accepts --json");
  }
  return ok({ json: flags.value.json });
}

function messageFromUnknown(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
