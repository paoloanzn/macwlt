import {
  createPublicClient,
  defineChain,
  http,
  type CallParameters,
  type HttpTransportConfig,
} from "viem";
import type { EthereumConfig } from "./EthereumConfig";
import type { EvmBlockTag, EvmCallRequest } from "./EvmCall";
import type { EvmCallTransport } from "./EthereumClient";

export type ViemTransportOptions = {
  readonly fetchFn?: HttpTransportConfig["fetchFn"];
};

export function createViemTransport(
  config: EthereumConfig,
  options: ViemTransportOptions = {},
): EvmCallTransport {
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
