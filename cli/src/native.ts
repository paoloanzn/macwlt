import { dlopen, ptr, read, type Pointer } from "bun:ffi";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { err, ok, type Result } from "./result";

const MACWLT_SUCCESS = 0;
const MACWLT_ERR_BUFFER_TOO_SMALL = 5;

const nativeSymbols = {
  macwlt_wallet_create: { args: ["ptr"], returns: "int" },
  macwlt_wallet_free: { args: ["ptr"], returns: "void" },
  macwlt_last_error: { args: ["ptr"], returns: "int" },
  macwlt_last_error_message: { args: ["ptr"], returns: "cstring" },
  macwlt_reset_wallet: { args: ["ptr"], returns: "int" },
  macwlt_bootstrap_wallet: { args: ["ptr", "ptr", "ptr"], returns: "int" },
  macwlt_sign_psbt: { args: ["ptr", "ptr", "usize", "ptr", "ptr"], returns: "int" },
  macwlt_sign_eth_tx: { args: ["ptr", "ptr", "usize", "ptr", "ptr"], returns: "int" },
  macwlt_export_pubkey: { args: ["ptr", "cstring", "ptr", "ptr"], returns: "int" },
  macwlt_export_address: { args: ["ptr", "cstring", "int", "ptr", "ptr"], returns: "int" },
} as const;

export type AddressType = "bitcoin" | "bitcoin-testnet" | "ethereum";

export type NativeError =
  | { readonly kind: "load"; readonly libraryPath: string; readonly message: string }
  | { readonly kind: "missing-library"; readonly libraryPath: string }
  | { readonly kind: "wallet-create"; readonly message: string }
  | { readonly kind: "native"; readonly operation: string; readonly code: number; readonly message: string }
  | { readonly kind: "oversized-output"; readonly operation: string; readonly size: bigint };

export type NativeClient = {
  readonly libraryPath: string;
  readonly close: () => void;
  readonly withWallet: <T, E>(body: (wallet: NativeWallet) => Result<T, E>) => Result<T, E | NativeError>;
};

export type NativeWallet = {
  readonly reset: () => Result<void, NativeError>;
  readonly bootstrap: () => Result<Uint8Array, NativeError>;
  readonly exportPubkey: (derivationPath: string) => Result<Uint8Array, NativeError>;
  readonly exportAddress: (derivationPath: string, addressType: AddressType) => Result<string, NativeError>;
  readonly signEthereumTransaction: (transaction: Uint8Array) => Result<Uint8Array, NativeError>;
  readonly signPsbt: (psbt: Uint8Array) => Result<Uint8Array, NativeError>;
};

type NativeLibrary = ReturnType<typeof dlopen<typeof nativeSymbols>>;
type NativeSymbols = NativeLibrary["symbols"];

export function defaultLibraryPath(envPath: string | undefined): string {
  if (envPath && envPath.length > 0) return resolve(envPath);

  const candidates = [
    resolve(join(process.cwd(), "build/libmacwlt.dylib")),
    resolve(join(process.cwd(), "../build/libmacwlt.dylib")),
    resolve(join(import.meta.dir, "../../build/libmacwlt.dylib")),
    resolve(join(import.meta.dir, "../../../build/libmacwlt.dylib")),
  ];
  return candidates.find((candidate) => existsSync(candidate)) ?? candidates[0] ?? resolve("build/libmacwlt.dylib");
}

export function openNativeClient(libraryPath: string): Result<NativeClient, NativeError> {
  if (!existsSync(libraryPath)) return err({ kind: "missing-library", libraryPath });

  let library: NativeLibrary;
  try {
    library = dlopen(libraryPath, nativeSymbols);
  } catch (caught: unknown) {
    return err({ kind: "load", libraryPath, message: messageFromUnknown(caught) });
  }

  const client: NativeClient = {
    libraryPath,
    close: () => library.close(),
    withWallet: <T, E>(body: (wallet: NativeWallet) => Result<T, E>): Result<T, E | NativeError> => {
      const walletResult = createWallet(library.symbols);
      if (!walletResult.ok) return walletResult;

      try {
        return body(walletResult.value);
      } finally {
        walletResult.value.close();
      }
    },
  };
  return ok(client);
}

function createWallet(symbols: NativeSymbols): Result<NativeWallet & { readonly close: () => void }, NativeError> {
  const walletSlot = new BigUint64Array(1);
  const createStatus = symbols.macwlt_wallet_create(ptr(walletSlot));
  const walletAddress = read.ptr(ptr(walletSlot));
  if (createStatus !== MACWLT_SUCCESS || walletAddress === 0) {
    return err({ kind: "wallet-create", message: "macwlt_wallet_create failed" });
  }

  const walletPointer = walletAddress as Pointer;
  const wallet: NativeWallet & { readonly close: () => void } = {
    close: () => {
      symbols.macwlt_wallet_free(walletPointer);
    },
    reset: () => {
      const status = symbols.macwlt_reset_wallet(walletPointer);
      if (status !== MACWLT_SUCCESS) {
        return err(nativeError(symbols, walletPointer, "reset wallet", symbols.macwlt_last_error(walletPointer)));
      }
      return ok(undefined);
    },
    bootstrap: () => outputBytes(symbols, walletPointer, "bootstrap", 33, (output, length) =>
      symbols.macwlt_bootstrap_wallet(walletPointer, output, length)
    ),
    exportPubkey: (derivationPath: string) =>
      outputBytes(symbols, walletPointer, "export pubkey", 33, (output, length) =>
        symbols.macwlt_export_pubkey(walletPointer, cString(derivationPath), output, length)
      ),
    exportAddress: (derivationPath: string, addressType: AddressType) => {
      const result = outputBytes(symbols, walletPointer, "export address", 96, (output, length) =>
        symbols.macwlt_export_address(walletPointer, cString(derivationPath), nativeAddressType(addressType), output, length)
      );
      if (!result.ok) return result;
      const terminator = result.value.indexOf(0);
      const addressBytes = terminator >= 0 ? result.value.slice(0, terminator) : result.value;
      return ok(new TextDecoder().decode(addressBytes));
    },
    signEthereumTransaction: (transaction: Uint8Array) =>
      outputBytes(symbols, walletPointer, "sign ethereum transaction", 65, (output, length) =>
        symbols.macwlt_sign_eth_tx(walletPointer, ptr(transaction), transaction.length, output, length)
      ),
    signPsbt: (psbt: Uint8Array) =>
      outputBytes(symbols, walletPointer, "sign psbt", Math.max(psbt.length + 1024, 1024), (output, length) =>
        symbols.macwlt_sign_psbt(walletPointer, ptr(psbt), psbt.length, output, length)
      ),
  };
  return ok(wallet);
}

function outputBytes(
  symbols: NativeSymbols,
  walletPointer: Pointer,
  operation: string,
  initialCapacity: number,
  call: (output: Pointer | null, length: Pointer) => number,
): Result<Uint8Array, NativeError> {
  const firstLength = new BigUint64Array([BigInt(initialCapacity)]);
  const firstBuffer = initialCapacity > 0 ? new Uint8Array(initialCapacity) : null;
  const firstStatus = call(firstBuffer ? ptr(firstBuffer) : null, ptr(firstLength));
  if (firstStatus === MACWLT_SUCCESS && firstBuffer) {
    const lengthResult = sizeFromSlot(operation, firstLength);
    if (!lengthResult.ok) return lengthResult;
    return ok(firstBuffer.slice(0, lengthResult.value));
  }

  const firstError = symbols.macwlt_last_error(walletPointer);
  if (firstError !== MACWLT_ERR_BUFFER_TOO_SMALL) {
    return err(nativeError(symbols, walletPointer, operation, firstError));
  }

  const requiredLength = sizeFromSlot(operation, firstLength);
  if (!requiredLength.ok) return requiredLength;
  const retryLength = new BigUint64Array([BigInt(requiredLength.value)]);
  const retryBuffer = new Uint8Array(requiredLength.value);
  const retryStatus = call(ptr(retryBuffer), ptr(retryLength));
  if (retryStatus !== MACWLT_SUCCESS) {
    return err(nativeError(symbols, walletPointer, operation, symbols.macwlt_last_error(walletPointer)));
  }

  const finalLength = sizeFromSlot(operation, retryLength);
  if (!finalLength.ok) return finalLength;
  return ok(retryBuffer.slice(0, finalLength.value));
}

function sizeFromSlot(operation: string, slot: BigUint64Array): Result<number, NativeError> {
  const size = slot[0] ?? 0n;
  if (size > BigInt(Number.MAX_SAFE_INTEGER)) {
    return err({ kind: "oversized-output", operation, size });
  }
  return ok(Number(size));
}

function cString(value: string): Uint8Array {
  const encoded = new TextEncoder().encode(value);
  const output = new Uint8Array(encoded.length + 1);
  output.set(encoded);
  return output;
}

function nativeAddressType(addressType: AddressType): number {
  switch (addressType) {
    case "bitcoin":
      return 1;
    case "bitcoin-testnet":
      return 2;
    case "ethereum":
      return 3;
  }
}

function nativeError(symbols: NativeSymbols, walletPointer: Pointer, operation: string, code: number): NativeError {
  const nativeMessage = symbols.macwlt_last_error_message(walletPointer);
  const message = nativeMessage ? nativeMessage.toString() : messageForNativeCode(code);
  return { kind: "native", operation, code, message };
}

function messageForNativeCode(code: number): string {
  switch (code) {
    case 1:
      return "invalid argument";
    case 2:
      return "wallet data is unavailable";
    case 3:
      return "authentication is required";
    case 4:
      return "authentication failed";
    case 5:
      return "output buffer is too small";
    case 6:
      return "operation is unsupported";
    case 7:
      return "input parsing failed";
    case 8:
      return "signing failed";
    case 9:
      return "internal native error";
    default:
      return `unknown native error ${code}`;
  }
}

function messageFromUnknown(caught: unknown): string {
  if (caught instanceof Error) return caught.message;
  return String(caught);
}
