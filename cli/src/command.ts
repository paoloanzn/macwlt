import { z } from "zod";
import { base64ToBytes, bytesToBase64 } from "./base64";
import { bytesToHex, hexToBytes } from "./hex";
import { defaultLibraryPath, openNativeClient, type AddressType, type NativeError } from "./native";
import { err, ok, type Result } from "./result";

const cliInputSchema = z.object({
  args: z.array(z.string()),
  env: z.object({ MACWLT_LIB: z.string().optional() }).passthrough(),
});

const version = "0.1.0";

export type CliResult = {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
};

export async function runCli(args: readonly string[], env: NodeJS.ProcessEnv = process.env): Promise<CliResult> {
  const input = cliInputSchema.safeParse({ args: [...args], env });
  if (!input.success) return failure("invalid process input");

  const commandResult = parseCommand(input.data.args);
  if (!commandResult.ok) return failure(commandResult.error);
  const command = commandResult.value;

  if (command.kind === "help") return success(helpText());
  if (command.kind === "version") return success(`macwlt ${version}`);

  const clientResult = openNativeClient(defaultLibraryPath(input.data.env.MACWLT_LIB));
  if (!clientResult.ok) return failure(formatNativeError(clientResult.error));

  const client = clientResult.value;
  try {
    const executionResult = await executeCommand(command, client);
    if (!executionResult.ok) return failure(executionResult.error);
    return success(executionResult.value);
  } finally {
    client.close();
  }
}

type Command =
  | { readonly kind: "help" }
  | { readonly kind: "version" }
  | { readonly kind: "create"; readonly reset: boolean; readonly json: boolean }
  | { readonly kind: "reset"; readonly json: boolean }
  | { readonly kind: "pubkey"; readonly derivationPath: string; readonly json: boolean }
  | { readonly kind: "address"; readonly derivationPath: string; readonly addressType: AddressType; readonly json: boolean }
  | { readonly kind: "sign-eth"; readonly input: BytesInput; readonly json: boolean }
  | { readonly kind: "sign-psbt"; readonly input: BytesInput; readonly output: OutputTarget; readonly format: PsbtOutputFormat; readonly json: boolean };

type BytesInput =
  | { readonly kind: "hex"; readonly value: string }
  | { readonly kind: "base64"; readonly value: string }
  | { readonly kind: "file"; readonly path: string };

type OutputTarget =
  | { readonly kind: "stdout" }
  | { readonly kind: "file"; readonly path: string };

type PsbtOutputFormat = "base64" | "hex" | "raw";

type NativeClientHandle = NonNullable<ReturnType<typeof openNativeClient> extends Result<infer T, NativeError> ? T : never>;

async function executeCommand(command: Exclude<Command, { readonly kind: "help" | "version" }>, client: NativeClientHandle): Promise<Result<string, string>> {
  switch (command.kind) {
    case "create":
      return withWalletText(client, (wallet) => {
        if (command.reset) {
          const reset = wallet.reset();
          if (!reset.ok) return err(formatNativeError(reset.error));
        }
        const publicKey = wallet.bootstrap();
        if (!publicKey.ok) return err(formatNativeError(publicKey.error));
        return ok(formatDataOutput(publicKey.value, command.json, "jointPublicKey"));
      });
    case "reset":
      return withWalletText(client, (wallet) => {
        const reset = wallet.reset();
        if (!reset.ok) return err(formatNativeError(reset.error));
        if (!command.json) return ok("wallet reset");
        return ok(JSON.stringify({ reset: true }, null, 2));
      });
    case "pubkey":
      return withWalletText(client, (wallet) => {
        const bootstrapped = wallet.bootstrap();
        if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
        const publicKey = wallet.exportPubkey(command.derivationPath);
        if (!publicKey.ok) return err(formatNativeError(publicKey.error));
        return ok(formatDataOutput(publicKey.value, command.json, "publicKey"));
      });
    case "address":
      return withWalletText(client, (wallet) => {
        const bootstrapped = wallet.bootstrap();
        if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
        const address = wallet.exportAddress(command.derivationPath, command.addressType);
        if (!address.ok) return err(formatNativeError(address.error));
        if (!command.json) return ok(address.value);
        return ok(JSON.stringify({ address: address.value, derivationPath: command.derivationPath, type: command.addressType }, null, 2));
      });
    case "sign-eth": {
      const transaction = await readInput(command.input);
      if (!transaction.ok) return transaction;
      return withWalletText(client, (wallet) => {
        const bootstrapped = wallet.bootstrap();
        if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
        const signature = wallet.signEthereumTransaction(transaction.value);
        if (!signature.ok) return err(formatNativeError(signature.error));
        return ok(formatDataOutput(signature.value, command.json, "signature"));
      });
    }
    case "sign-psbt": {
      const psbt = await readInput(command.input);
      if (!psbt.ok) return psbt;
      const signed = client.withWallet<Uint8Array, string>((wallet) => {
        const bootstrapped = wallet.bootstrap();
        if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
        const signedPsbt = wallet.signPsbt(psbt.value);
        if (!signedPsbt.ok) return err(formatNativeError(signedPsbt.error));
        return ok(signedPsbt.value);
      });
      if (!signed.ok) return err(formatExecutionError(signed.error));

      if (command.output.kind === "file") {
        const bytes = command.format === "raw" ? signed.value : new TextEncoder().encode(formatPsbt(signed.value, command.format));
        await Bun.write(command.output.path, bytes);
        return ok(command.json ? JSON.stringify({ output: command.output.path, format: command.format }, null, 2) : command.output.path);
      }
      if (command.format === "raw") return err("--format raw requires --out <file>");
      if (command.json) return ok(JSON.stringify({ signedPsbt: formatPsbt(signed.value, command.format), format: command.format }, null, 2));
      return ok(formatPsbt(signed.value, command.format));
    }
  }
}

function withWalletText(
  client: NativeClientHandle,
  body: (wallet: Parameters<Parameters<NativeClientHandle["withWallet"]>[0]>[0]) => Result<string, string>,
): Result<string, string> {
  const result = client.withWallet<string, string>(body);
  if (!result.ok) return err(formatExecutionError(result.error));
  return ok(result.value);
}

function parseCommand(args: readonly string[]): Result<Command, string> {
  const [name, ...rest] = args;
  if (!name || name === "help" || name === "--help" || name === "-h") return ok({ kind: "help" });
  if (name === "version" || name === "--version" || name === "-v") return ok({ kind: "version" });

  switch (name) {
    case "create":
      return parseCreate(rest);
    case "reset":
      return parseReset(rest);
    case "pubkey":
      return parsePubkey(rest);
    case "address":
      return parseAddress(rest);
    case "sign-eth":
      return parseSignEth(rest);
    case "sign-psbt":
      return parseSignPsbt(rest);
    default:
      return err(`unknown command: ${name}\n\n${helpText()}`);
  }
}

function parseCreate(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("create does not accept positional arguments");
  return ok({ kind: "create", reset: flags.value.switches.has("reset"), json: flags.value.json });
}

function parseReset(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("reset does not accept positional arguments");
  if (!flags.value.switches.has("yes")) return err("reset requires --yes");
  return ok({ kind: "reset", json: flags.value.json });
}

function parsePubkey(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 1) return err("pubkey accepts at most one derivation path");
  return ok({ kind: "pubkey", derivationPath: flags.value.positionals[0] ?? "m", json: flags.value.json });
}

function parseAddress(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 1) return err("address accepts at most one derivation path");
  const type = flags.value.options.get("type");
  if (!isAddressType(type)) return err("address requires --type bitcoin|bitcoin-testnet|ethereum");
  return ok({ kind: "address", derivationPath: flags.value.positionals[0] ?? "m", addressType: type, json: flags.value.json });
}

function parseSignEth(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("sign-eth does not accept positional arguments");
  const input = parseBytesInput(flags.value.options, ["hex", "in"]);
  if (!input.ok) return input;
  return ok({ kind: "sign-eth", input: input.value, json: flags.value.json });
}

function parseSignPsbt(args: readonly string[]): Result<Command, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 0) return err("sign-psbt does not accept positional arguments");
  const input = parseBytesInput(flags.value.options, ["base64", "hex", "in"]);
  if (!input.ok) return input;
  const format = flags.value.options.get("format") ?? "base64";
  if (!isPsbtOutputFormat(format)) return err("--format must be base64, hex, or raw");
  const out = flags.value.options.get("out");
  return ok({
    kind: "sign-psbt",
    input: input.value,
    output: out ? { kind: "file", path: out } : { kind: "stdout" },
    format,
    json: flags.value.json,
  });
}

type ParsedFlags = {
  readonly json: boolean;
  readonly positionals: readonly string[];
  readonly options: ReadonlyMap<string, string>;
  readonly switches: ReadonlySet<string>;
};

function parseFlags(args: readonly string[]): Result<ParsedFlags, string> {
  let json = false;
  const positionals: string[] = [];
  const options = new Map<string, string>();
  const switches = new Set<string>();

  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (!arg) continue;
    if (arg === "--json") {
      json = true;
      continue;
    }
    if (arg === "--reset" || arg === "--yes") {
      switches.add(arg.slice(2));
      continue;
    }
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }

    const key = arg.slice(2);
    if (key.length === 0) return err("empty option name");
    const value = args[index + 1];
    if (!value || value.startsWith("--")) return err(`missing value for --${key}`);
    options.set(key, value);
    index++;
  }

  return ok({ json, positionals, options, switches });
}

function parseBytesInput(options: ReadonlyMap<string, string>, allowed: readonly string[]): Result<BytesInput, string> {
  const entries = allowed.flatMap((key) => {
    const value = options.get(key);
    return value ? [{ key, value }] : [];
  });
  if (entries.length !== 1) return err(`provide exactly one input option: ${allowed.map((key) => `--${key}`).join(", ")}`);

  const input = entries[0];
  if (!input) return err("missing input");
  if (input.key === "hex") return ok({ kind: "hex", value: input.value });
  if (input.key === "base64") return ok({ kind: "base64", value: input.value });
  return ok({ kind: "file", path: input.value });
}

async function readInput(input: BytesInput): Promise<Result<Uint8Array, string>> {
  switch (input.kind) {
    case "hex": {
      const decoded = hexToBytes(input.value);
      if (!decoded.ok) return err(decoded.error.kind === "empty" ? "hex input is empty" : `invalid hex input: ${decoded.error.value}`);
      return decoded;
    }
    case "base64": {
      const decoded = base64ToBytes(input.value);
      if (!decoded.ok) return err(decoded.error.kind === "empty" ? "base64 input is empty" : "invalid base64 input");
      return decoded;
    }
    case "file": {
      try {
        return ok(new Uint8Array(await Bun.file(input.path).arrayBuffer()));
      } catch (caught: unknown) {
        return err(`failed to read ${input.path}: ${caught instanceof Error ? caught.message : String(caught)}`);
      }
    }
  }
}

function isAddressType(value: string | undefined): value is AddressType {
  return value === "bitcoin" || value === "bitcoin-testnet" || value === "ethereum";
}

function isPsbtOutputFormat(value: string): value is PsbtOutputFormat {
  return value === "base64" || value === "hex" || value === "raw";
}

function formatDataOutput(bytes: Uint8Array, json: boolean, key: string): string {
  const hex = bytesToHex(bytes);
  if (!json) return hex;
  return JSON.stringify({ [key]: hex }, null, 2);
}

function formatPsbt(bytes: Uint8Array, format: Exclude<PsbtOutputFormat, "raw">): string {
  return format === "base64" ? bytesToBase64(bytes) : bytesToHex(bytes);
}

function formatNativeError(error: NativeError): string {
  switch (error.kind) {
    case "missing-library":
      return `native library not found at ${error.libraryPath}; run make build or set MACWLT_LIB`;
    case "load":
      return `failed to load ${error.libraryPath}: ${error.message}`;
    case "wallet-create":
      return error.message;
    case "native":
      return `${error.operation} failed: ${error.message}`;
    case "oversized-output":
      return `${error.operation} produced an oversized output (${error.size.toString()} bytes)`;
  }
}

function formatExecutionError(error: string | NativeError): string {
  return typeof error === "string" ? error : formatNativeError(error);
}

function formatPsbtHelp(): string {
  return [
    "  macwlt sign-psbt --base64 <psbt> [--format base64|hex] [--json]",
    "  macwlt sign-psbt --hex <psbt-hex> [--out <file>] [--format base64|hex|raw]",
    "  macwlt sign-psbt --in <file> [--out <file>] [--format base64|hex|raw]",
  ].join("\n");
}

function helpText(): string {
  return [
    "Usage:",
    "  macwlt create [--reset] [--json]",
    "  macwlt reset --yes [--json]",
    "  macwlt pubkey [path] [--json]",
    "  macwlt address [path] --type bitcoin|bitcoin-testnet|ethereum [--json]",
    "  macwlt sign-eth --hex <typed-transaction-preimage-hex> [--json]",
    formatPsbtHelp(),
    "  macwlt version",
    "",
    "Environment:",
    "  MACWLT_LIB  Path to libmacwlt.dylib (default: ./build/libmacwlt.dylib)",
  ].join("\n");
}

function success(stdout: string): CliResult {
  return { exitCode: 0, stdout: `${stdout}\n`, stderr: "" };
}

function failure(stderr: string): CliResult {
  return { exitCode: 1, stdout: "", stderr: `${stderr}\n` };
}
