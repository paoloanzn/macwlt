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
import { err, ok, type Result } from "../result";

export interface EvmCallTransport {
  call(request: EvmCallRequest): Promise<unknown>;
}

export type EvmCallTransportFactory = (config: EthereumConfig) => EvmCallTransport;

export type EthereumClientCreationError =
  | EthereumConfigError
  | { readonly kind: "transport-creation-failed"; readonly cause: unknown };

export type EthereumCallError =
  | { readonly kind: "invalid-request"; readonly message: string }
  | { readonly kind: "transport-failed"; readonly cause: unknown }
  | { readonly kind: "invalid-response"; readonly message: string };

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
}
