import {
  parseEthereumConfig,
  type EthereumConfig,
  type EthereumConfigError,
  type EthereumConfigInput,
} from "./EthereumConfig";
import {
  parseEvmCallRequest,
  parseEvmCallResult,
  type EvmCallRequest,
  type EvmCallResult,
} from "./EvmCall";
import type {
  EvmTransactionRequest,
  TransactionHash,
} from "./EvmTransaction";
import { err, ok, type Result } from "../result";
import { z } from "zod";

export interface EvmCallTransport {
  call(request: EvmCallRequest): Promise<unknown>;
}

export interface EvmTransport extends EvmCallTransport {
  getChainId(): Promise<unknown>;
  getTransactionCount(address: string): Promise<unknown>;
  getBalance(address: string): Promise<unknown>;
  estimateGas(request: EvmTransactionRequest): Promise<unknown>;
  getGasPrice(): Promise<unknown>;
  sendRawTransaction(transaction: string): Promise<unknown>;
}

export type EvmCallTransportFactory = (config: EthereumConfig) => EvmCallTransport;

export type EthereumClientCreationError =
  | EthereumConfigError
  | { readonly kind: "transport-creation-failed"; readonly cause: unknown };

export type EthereumCallError =
  | { readonly kind: "invalid-request"; readonly message: string }
  | { readonly kind: "transport-failed"; readonly cause: unknown }
  | { readonly kind: "invalid-response"; readonly message: string };

export type EthereumTransactionOperation =
  | "get-chain-id"
  | "get-transaction-count"
  | "get-balance"
  | "estimate-gas"
  | "get-gas-price"
  | "send-raw-transaction";

export type EthereumTransactionError =
  | { readonly kind: "unsupported-transport" }
  | { readonly kind: "invalid-request"; readonly message: string }
  | {
    readonly kind: "transport-failed";
    readonly operation: EthereumTransactionOperation;
    readonly cause: unknown;
  }
  | {
    readonly kind: "invalid-response";
    readonly operation: EthereumTransactionOperation;
    readonly message: string;
  }
  | {
    readonly kind: "chain-mismatch";
    readonly expected: number;
    readonly actual: number;
  };

const addressSchema = z.string().regex(/^0x[0-9a-fA-F]{40}$/);
const transactionRequestSchema = z.object({
  from: addressSchema,
  to: addressSchema,
  data: z.string().regex(/^0x(?:[0-9a-fA-F]{2})*$/).optional(),
  value: z.bigint().nonnegative().optional(),
}).strict();
const chainIdSchema = z.number().int().positive().safe();
const transactionCountSchema = z.number().int().nonnegative().safe();
const quantitySchema = z.bigint().nonnegative();
const transactionHashSchema = z.custom<TransactionHash>(
  (value) =>
    typeof value === "string"
    && /^0x[0-9a-fA-F]{64}$/.test(value),
);

export class EthereumClient {
  readonly #config: EthereumConfig;
  readonly #transport: EvmCallTransport;

  private constructor(config: EthereumConfig, transport: EvmCallTransport) {
    this.#config = config;
    this.#transport = transport;
  }

  static create(
    input: EthereumConfigInput,
    createTransport: EvmCallTransportFactory,
  ): Result<EthereumClient, EthereumClientCreationError> {
    const config = parseEthereumConfig(input);
    if (!config.ok) return config;

    try {
      return ok(new EthereumClient(config.value, createTransport(config.value)));
    } catch (cause: unknown) {
      return err({ kind: "transport-creation-failed", cause });
    }
  }

  get config(): EthereumConfig {
    return this.#config;
  }

  async call(
    request: EvmCallRequest,
  ): Promise<Result<EvmCallResult, EthereumCallError>> {
    const parsedRequest = parseEvmCallRequest(request);
    if (!parsedRequest.ok) {
      return err({ kind: "invalid-request", message: parsedRequest.error.message });
    }

    let response: unknown;
    try {
      response = await this.#transport.call(parsedRequest.value);
    } catch (cause: unknown) {
      return err({ kind: "transport-failed", cause });
    }

    const parsedResponse = parseEvmCallResult(response);
    if (!parsedResponse.ok) {
      return err({ kind: "invalid-response", message: parsedResponse.error.message });
    }
    return ok(parsedResponse.value);
  }

  async verifyChain(): Promise<Result<void, EthereumTransactionError>> {
    const chainId = await this.#performTransactionOperation(
      "get-chain-id",
      (transport) => transport.getChainId(),
      chainIdSchema,
    );
    if (!chainId.ok) return chainId;
    if (chainId.value !== this.#config.chainId) {
      return err({
        kind: "chain-mismatch",
        expected: this.#config.chainId,
        actual: chainId.value,
      });
    }
    return ok(undefined);
  }

  async getTransactionCount(
    address: string,
  ): Promise<Result<number, EthereumTransactionError>> {
    if (!addressSchema.safeParse(address).success) {
      return err({ kind: "invalid-request", message: "invalid Ethereum address" });
    }
    return await this.#performTransactionOperation(
      "get-transaction-count",
      (transport) => transport.getTransactionCount(address),
      transactionCountSchema,
    );
  }

  async estimateGas(
    request: EvmTransactionRequest,
  ): Promise<Result<bigint, EthereumTransactionError>> {
    const parsed = transactionRequestSchema.safeParse(request);
    if (!parsed.success) {
      return err({
        kind: "invalid-request",
        message: parsed.error.issues.map((issue) => issue.message).join("; "),
      });
    }
    return await this.#performTransactionOperation(
      "estimate-gas",
      (transport) =>
        transport.estimateGas(parsed.data as EvmTransactionRequest),
      quantitySchema,
    );
  }

  async getBalance(
    address: string,
  ): Promise<Result<bigint, EthereumTransactionError>> {
    if (!addressSchema.safeParse(address).success) {
      return err({ kind: "invalid-request", message: "invalid Ethereum address" });
    }
    return await this.#performTransactionOperation(
      "get-balance",
      (transport) => transport.getBalance(address),
      quantitySchema,
    );
  }

  async getGasPrice(): Promise<Result<bigint, EthereumTransactionError>> {
    return await this.#performTransactionOperation(
      "get-gas-price",
      (transport) => transport.getGasPrice(),
      quantitySchema,
    );
  }

  async sendRawTransaction(
    transaction: string,
  ): Promise<Result<TransactionHash, EthereumTransactionError>> {
    if (!/^0x(?:[0-9a-fA-F]{2})+$/.test(transaction)) {
      return err({ kind: "invalid-request", message: "invalid serialized transaction" });
    }
    return await this.#performTransactionOperation(
      "send-raw-transaction",
      (transport) => transport.sendRawTransaction(transaction),
      transactionHashSchema,
    );
  }

  async #performTransactionOperation<T>(
    operation: EthereumTransactionOperation,
    perform: (transport: EvmTransport) => Promise<unknown>,
    schema: z.ZodType<T>,
  ): Promise<Result<T, EthereumTransactionError>> {
    if (!isEvmTransport(this.#transport)) {
      return err({ kind: "unsupported-transport" });
    }

    let response: unknown;
    try {
      response = await perform(this.#transport);
    } catch (cause: unknown) {
      return err({ kind: "transport-failed", operation, cause });
    }

    const parsed = schema.safeParse(response);
    if (!parsed.success) {
      return err({
        kind: "invalid-response",
        operation,
        message: parsed.error.issues.map((issue) => issue.message).join("; "),
      });
    }
    return ok(parsed.data);
  }
}

function isEvmTransport(transport: EvmCallTransport): transport is EvmTransport {
  const candidate = transport as Partial<EvmTransport>;
  return typeof candidate.getChainId === "function"
    && typeof candidate.getTransactionCount === "function"
    && typeof candidate.getBalance === "function"
    && typeof candidate.estimateGas === "function"
    && typeof candidate.getGasPrice === "function"
    && typeof candidate.sendRawTransaction === "function";
}
