import type { NativeClient, NativeWallet } from "./native";
import { err, ok, type Result } from "./result";
import { formatExecutionError } from "./nativeError";

export function runWithWallet<T>(
  client: NativeClient,
  body: (wallet: NativeWallet) => Result<T, string>,
): Result<T, string> {
  const result = client.withWallet<T, string>(body);
  if (!result.ok) return err(formatExecutionError(result.error));
  return ok(result.value);
}