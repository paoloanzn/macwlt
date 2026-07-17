import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { runWithWallet } from "../withWallet";
import { formatDataOutput } from "../walletOutput";
import { formatNativeError } from "../nativeError";
import type { Command, CommandContext } from "../command";

export type CreateArgs = { readonly reset: boolean; readonly json: boolean };

export const createCommand: Command<CreateArgs> = {
  name: "create",
  describe(): string {
    return "  macwlt create [--reset] [--json]";
  },
  parse: parseCreate,
  async run(ctx: CommandContext, args: CreateArgs): Promise<Result<string, string>> {
    const result = runWithWallet<string>(ctx.client, (wallet) => {
      if (args.reset) {
        const reset = wallet.reset();
        if (!reset.ok) return err(formatNativeError(reset.error));
      }
      const publicKey = wallet.bootstrap();
      if (!publicKey.ok) return err(formatNativeError(publicKey.error));
      return ok(formatDataOutput(publicKey.value, args.json, "jointPublicKey"));
    });
    return result;
  },
};

function parseCreate(args: readonly string[]): Result<CreateArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("create does not accept positional arguments");
  return ok({ reset: flags.value.switches.has("reset"), json: flags.value.json });
}