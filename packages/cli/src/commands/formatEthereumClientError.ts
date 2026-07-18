import type {
  EthereumCallError,
  EthereumTransactionError,
} from "../ethereum";

export function formatEthereumClientError(
  error: EthereumCallError | EthereumTransactionError,
): string {
  switch (error.kind) {
    case "unsupported-transport":
      return "configured Ethereum transport does not support transactions";
    case "invalid-request":
      return error.message;
    case "transport-failed":
      return messageFromUnknown(error.cause);
    case "invalid-response":
      return error.message;
    case "chain-mismatch":
      return `RPC node reports chain ${error.actual}, expected ${error.expected}`;
  }
}

function messageFromUnknown(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
