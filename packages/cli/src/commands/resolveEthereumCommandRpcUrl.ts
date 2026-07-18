import { GlobalConfig, type GlobalConfigLoadError } from "../config";
import { resolveEthereumRpcUrl } from "../ethereum";
import { err, ok, type Result } from "../result";

export async function resolveEthereumCommandRpcUrl(
  env: NodeJS.ProcessEnv,
  chainId: number,
  explicitRpcUrl: string | undefined,
): Promise<Result<string, string>> {
  if (explicitRpcUrl !== undefined) return ok(explicitRpcUrl);

  const homeDirectory = env.HOME?.length ? env.HOME : undefined;
  const loaded = await GlobalConfig.load({ homeDirectory });
  if (!loaded.ok) return err(formatConfigLoadError(loaded.error));
  const rpcUrl = resolveEthereumRpcUrl(loaded.value.data, chainId);
  if (!rpcUrl.ok) {
    const configPath = loaded.value.path;
    return err(
      rpcUrl.error.kind === "missing-chain-rpc"
        ? `no RPC configured for chain ${chainId} in ${configPath}; set ethereum.chains.${chainId}.rpcUrl or pass --rpc`
        : `invalid RPC configured for chain ${chainId} in ${configPath}`,
    );
  }
  return ok(rpcUrl.value);
}

function formatConfigLoadError(error: GlobalConfigLoadError): string {
  switch (error.kind) {
    case "read-failed":
      return `failed to read global config ${error.path}: ${messageFromUnknown(error.cause)}`;
    case "invalid-json":
      return `invalid JSON in global config ${error.path}: ${error.message}`;
    case "invalid-config":
      return `invalid global config ${error.path}: ${error.message}`;
  }
}

function messageFromUnknown(value: unknown): string {
  return value instanceof Error ? value.message : String(value);
}
