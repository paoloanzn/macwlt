import { isAddress } from "viem";
import type { EthereumAddress } from "../ethereum";
import { formatNativeError } from "../nativeError";
import type { NativeClient } from "../native";
import { err, ok, type Result } from "../result";
import { runWithWallet } from "../withWallet";

export function ethereumWalletAddress(
  client: NativeClient,
  derivationPath: string,
): Result<EthereumAddress, string> {
  const address = runWithWallet<string>(client, (wallet) => {
    const bootstrapped = wallet.bootstrap();
    if (!bootstrapped.ok) return err(formatNativeError(bootstrapped.error));
    const exported = wallet.exportAddress(derivationPath, "ethereum");
    if (!exported.ok) return err(formatNativeError(exported.error));
    return ok(exported.value);
  });
  if (!address.ok) return address;
  if (!isAddress(address.value)) {
    return err("native wallet returned an invalid Ethereum address");
  }
  return ok(address.value);
}
