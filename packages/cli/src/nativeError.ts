import type { NativeError } from "./native";

export function formatNativeError(error: NativeError): string {
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

export function formatExecutionError(error: string | NativeError): string {
  return typeof error === "string" ? error : formatNativeError(error);
}