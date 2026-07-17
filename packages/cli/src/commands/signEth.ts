import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { readInput, parseBytesInput, type BytesInput } from "../bytesInput";
import { runWithWallet } from "../withWallet";
import { formatDataOutput } from "../walletOutput";
import { formatNativeError } from "../nativeError";
import type { Command, CommandContext } from "../command";

export type SignEthArgs = { readonly input: BytesInput; readonly json: boolean };

export const signEthCommand: Command<SignEthArgs> = {
  name: "sign-eth",
  describe(): string {
    return "  macwlt sign-eth --hex <typed-transaction-preimage-hex> [--json]";
  },
  parse: parseSignEth,
  async run(ctx: CommandContext, args: SignEthArgs): Promise<Result<string, string>> {
    const transaction = await readInput(args.input);
    if (!transaction.ok) return transaction;
    return runWithWallet<string>(ctx.client, (wallet) => {
      const bootstrapped = wallet.bootstrap();
      if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
      const signature = wallet.signEthereumTransaction(transaction.value);
      if (!signature.ok) return err(formatNativeError(signature.error));
      return ok(formatDataOutput(signature.value, args.json, "signature"));
    });
  },
};

function parseSignEth(args: readonly string[]): Result<SignEthArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("sign-eth does not accept positional arguments");
  const input = parseBytesInput(flags.value.options, ["hex", "in"]);
  if (!input.ok) return input;
  return ok({ input: input.value, json: flags.value.json });
}