import {
  createPublicClient,
  defineChain,
  http,
  type CallParameters,
  type HttpTransportConfig,
} from "viem";
import type { EthereumConfig } from "./EthereumConfig";
import type { EvmBlockTag, EvmCallRequest } from "./EvmCall";
import type { EvmTransport } from "./EthereumClient";
import type { EvmTransactionRequest } from "./EvmTransaction";

export type ViemTransportOptions = {
  readonly fetchFn?: HttpTransportConfig["fetchFn"];
};

export function createViemTransport(
  config: EthereumConfig,
  options: ViemTransportOptions = {},
): EvmTransport {
  const chain = defineChain({
    id: config.chainId,
    name: `Chain ${config.chainId}`,
    nativeCurrency: { name: "Native Currency", symbol: "NATIVE", decimals: 18 },
    rpcUrls: { default: { http: [config.rpcUrl] } },
  });
  const client = createPublicClient({
    chain,
    transport: http(config.rpcUrl, { fetchFn: options.fetchFn }),
  });

  return {
    async call(request: EvmCallRequest): Promise<unknown> {
      const response = await client.call(toViemCallParameters(request));
      return { data: response.data };
    },
    async getChainId(): Promise<unknown> {
      return await client.getChainId();
    },
    async getTransactionCount(address: string): Promise<unknown> {
      return await client.getTransactionCount({
        address: address as `0x${string}`,
        blockTag: "pending",
      });
    },
    async getBalance(address: string): Promise<unknown> {
      return await client.getBalance({
        address: address as `0x${string}`,
        blockTag: "pending",
      });
    },
    async estimateGas(request: EvmTransactionRequest): Promise<unknown> {
      return await client.estimateGas({
        account: request.from,
        to: request.to,
        data: request.data,
        value: request.value,
      });
    },
    async getGasPrice(): Promise<unknown> {
      return await client.getGasPrice();
    },
    async sendRawTransaction(transaction: string): Promise<unknown> {
      return await client.sendRawTransaction({
        serializedTransaction: transaction as `0x${string}`,
      });
    },
  };
}

function toViemCallParameters(request: EvmCallRequest): CallParameters {
  const block = typeof request.block === "bigint"
    ? { blockNumber: request.block }
    : typeof request.block === "string"
      ? { blockTag: request.block as EvmBlockTag }
      : {};
  const parameters = {
    to: request.to,
    data: request.data,
    account: request.from,
    gas: request.gas,
    value: request.value,
    ...block,
  };

  return request.gasPrice === undefined
    ? parameters
    : { ...parameters, type: "legacy", gasPrice: request.gasPrice };
}
