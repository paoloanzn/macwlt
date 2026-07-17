import { z } from "zod";
import type { GlobalConfigData } from "../config/parseGlobalConfigData";
import { parseEthereumConfig, type RpcUrl } from "./EthereumConfig";
import { err, ok, type Result } from "../result";

export type EthereumRpcResolutionError =
  | { readonly kind: "missing-chain-rpc"; readonly chainId: number }
  | { readonly kind: "invalid-chain-rpc"; readonly chainId: number };

const ethereumChainsSchema = z.object({
  ethereum: z.object({
    chains: z.record(z.object({
      rpcUrl: z.string(),
    }).passthrough()),
  }).passthrough(),
}).passthrough();

export function resolveEthereumRpcUrl(
  config: GlobalConfigData,
  chainId: number,
): Result<RpcUrl, EthereumRpcResolutionError> {
  const parsed = ethereumChainsSchema.safeParse(config);
  if (!parsed.success) {
    return err({ kind: "missing-chain-rpc", chainId });
  }
  const rpcUrl = parsed.data.ethereum.chains[String(chainId)]?.rpcUrl;
  if (!rpcUrl) return err({ kind: "missing-chain-rpc", chainId });

  const ethereumConfig = parseEthereumConfig({ rpcUrl, chainId });
  if (!ethereumConfig.ok) {
    return err({ kind: "invalid-chain-rpc", chainId });
  }
  return ok(ethereumConfig.value.rpcUrl);
}
