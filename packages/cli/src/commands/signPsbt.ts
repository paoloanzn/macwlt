import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { readInput, parseBytesInput, type BytesInput } from "../bytesInput";
import { runWithWallet } from "../withWallet";
import { formatPsbt, type PsbtTextFormat } from "../walletOutput";
import { formatNativeError } from "../nativeError";
import type { Command, CommandContext } from "../command";

export type PsbtOutputFormat = PsbtTextFormat | "raw";

type OutputTarget =
  | { readonly kind: "stdout" }
  | { readonly kind: "file"; readonly path: string };

export type SignPsbtArgs = {
  readonly input: BytesInput;
  readonly output: OutputTarget;
  readonly format: PsbtOutputFormat;
  readonly json: boolean;
};

export const signPsbtCommand: Command<SignPsbtArgs> = {
  name: "sign-psbt",
  describe(): string {
    return [
      "  macwlt sign-psbt --base64 <psbt> [--format base64|hex] [--json]",
      "  macwlt sign-psbt --hex <psbt-hex> [--out <file>] [--format base64|hex|raw]",
      "  macwlt sign-psbt --in <file> [--out <file>] [--format base64|hex|raw]",
    ].join("\n");
  },
  parse: parseSignPsbt,
  async run(ctx: CommandContext, args: SignPsbtArgs): Promise<Result<string, string>> {
    const psbt = await readInput(args.input);
    if (!psbt.ok) return psbt;
    const signedResult = runWithWallet<Uint8Array>(ctx.client, (wallet) => {
      const bootstrapped = wallet.bootstrap();
      if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
      const signedPsbt = wallet.signPsbt(psbt.value);
      if (!signedPsbt.ok) return err(formatNativeError(signedPsbt.error));
      return ok(signedPsbt.value);
    });
    if (!signedResult.ok) return signedResult;

    if (args.output.kind === "file") {
      const bytes = args.format === "raw"
        ? signedResult.value
        : new TextEncoder().encode(formatPsbt(signedResult.value, args.format));
      await Bun.write(args.output.path, bytes);
      return ok(args.json
        ? JSON.stringify({ output: args.output.path, format: args.format }, null, 2)
        : args.output.path);
    }

    if (args.format === "raw") return err("--format raw requires --out <file>");
    if (args.json) return ok(JSON.stringify({ signedPsbt: formatPsbt(signedResult.value, args.format), format: args.format }, null, 2));
    return ok(formatPsbt(signedResult.value, args.format));
  },
};

function parseSignPsbt(args: readonly string[]): Result<SignPsbtArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("sign-psbt does not accept positional arguments");
  const input = parseBytesInput(flags.value.options, ["base64", "hex", "in"]);
  if (!input.ok) return input;
  const format = flags.value.options.get("format") ?? "base64";
  if (!isPsbtOutputFormat(format)) return err("--format must be base64, hex, or raw");
  const out = flags.value.options.get("out");
  return ok({
    input: input.value,
    output: out ? { kind: "file", path: out } : { kind: "stdout" },
    format,
    json: flags.value.json,
  });
}

export function isPsbtOutputFormat(value: string): value is PsbtOutputFormat {
  return value === "base64" || value === "hex" || value === "raw";
}