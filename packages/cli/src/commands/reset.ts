import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { runWithWallet } from "../withWallet";
import { formatNativeError } from "../nativeError";
import type { Command, CommandContext } from "../command";

export type ResetArgs = { readonly json: boolean };

export const resetCommand: Command<ResetArgs> = {
  name: "reset",
  describe(): string {
    return "  macwlt reset --yes [--json]";
  },
  parse: parseReset,
  async run(ctx: CommandContext, args: ResetArgs): Promise<Result<string, string>> {
    return runWithWallet<string>(ctx.client, (wallet) => {
      const reset = wallet.reset();
      if (!reset.ok) return err(formatNativeError(reset.error));
      if (!args.json) return ok("wallet reset");
      return ok(JSON.stringify({ reset: true }, null, 2));
    });
  },
};

function parseReset(args: readonly string[]): Result<ResetArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("reset does not accept positional arguments");
  if (!flags.value.switches.has("yes")) return err("reset requires --yes");
  return ok({ json: flags.value.json });
}