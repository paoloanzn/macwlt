import { err, ok, type Result } from "../result";
import { parseFlags } from "../parseFlags";
import { runWithWallet } from "../withWallet";
import { formatNativeError } from "../nativeError";
import type { AddressType } from "../native";
import type { Command, CommandContext } from "../command";

export type AddressArgs = {
  readonly derivationPath: string;
  readonly addressType: AddressType;
  readonly json: boolean;
};

export const addressCommand: Command<AddressArgs> = {
  name: "address",
  describe(): string {
    return "  macwlt address [path] --type bitcoin|bitcoin-testnet|bitcoin-taproot|bitcoin-taproot-testnet|ethereum [--json]";
  },
  parse: parseAddress,
  async run(ctx: CommandContext, args: AddressArgs): Promise<Result<string, string>> {
    return runWithWallet<string>(ctx.client, (wallet) => {
      const bootstrapped = wallet.bootstrap();
      if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
      const address = wallet.exportAddress(args.derivationPath, args.addressType);
      if (!address.ok) return err(formatNativeError(address.error));
      if (!args.json) return ok(address.value);
      return ok(JSON.stringify({ address: address.value, derivationPath: args.derivationPath, type: args.addressType }, null, 2));
    });
  },
};

function parseAddress(args: readonly string[]): Result<AddressArgs, string> {
  const flags = parseFlags(args);
  if (!flags.ok) return flags;
  if (flags.value.positionals.length > 1) return err("address accepts at most one derivation path");
  const type = flags.value.options.get("type");
  if (!isAddressType(type)) {
    return err(
      "address requires --type bitcoin|bitcoin-testnet|bitcoin-taproot|bitcoin-taproot-testnet|ethereum",
    );
  }
  return ok({ derivationPath: flags.value.positionals[0] ?? "m", addressType: type, json: flags.value.json });
}

export function isAddressType(value: string | undefined): value is AddressType {
  return value === "bitcoin"
    || value === "bitcoin-testnet"
    || value === "bitcoin-taproot"
    || value === "bitcoin-taproot-testnet"
    || value === "ethereum";
}