import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { runWithWallet } from "../withWallet";
import { formatDataOutput } from "../walletOutput";
import { formatNativeError } from "../nativeError";
import type { Command, CommandContext } from "../command";

export type PubkeyArgs = { readonly derivationPath: string; readonly json: boolean };

export const pubkeyCommand: Command<PubkeyArgs> = {
  name: "pubkey",
  describe(): string {
    return "  macwlt pubkey [path] [--json]";
  },
  parse: parsePubkey,
  async run(ctx: CommandContext, args: PubkeyArgs): Promise<Result<string, string>> {
    return runWithWallet<string>(ctx.client, (wallet) => {
      const bootstrapped = wallet.bootstrap();
      if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
      const publicKey = wallet.exportPubkey(args.derivationPath);
      if (!publicKey.ok) return err(formatNativeError(publicKey.error));
      return ok(formatDataOutput(publicKey.value, args.json, "publicKey"));
    });
  },
};

function parsePubkey(args: readonly string[]): Result<PubkeyArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 1) return err("pubkey accepts at most one derivation path");
  return ok({ derivationPath: flags.value.positionals[0] ?? "m", json: flags.value.json });
}