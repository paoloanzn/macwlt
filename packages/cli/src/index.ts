export { bytesToBase64, base64ToBytes, type Base64Error } from "./base64";
export {
  runCli,
  helpText,
  cliVersion,
  type Command,
  type CommandHook,
  type CommandContext,
  type CliResult,
  type RunCliOptions,
} from "./command";
export { commands } from "./commands";
export { bytesToHex, hexToBytes, type HexError } from "./hex";
export { defaultLibraryPath, openNativeClient, type AddressType, type NativeClient, type NativeError, type NativeWallet } from "./native";
export { err, ok, type Result } from "./result";
export { parseFlags, type ParsedFlags } from "./parseFlags";
export { parseBytesInput, readInput, type BytesInput } from "./bytesInput";
export { formatNativeError, formatExecutionError } from "./nativeError";
export { formatDataOutput, formatPsbt, type PsbtTextFormat } from "./walletOutput";
export { runWithWallet } from "./withWallet";
export { createConfirmationHook } from "./hooks/createConfirmationHook";
export {
  terminalConfirmationPrompt,
  type ConfirmationPrompt,
} from "./terminalConfirmationPrompt";
export * from "./config";
export * from "./ethereum";
