import {
  EthereumClient,
  type EthereumClientCreationError,
  type EvmCallTransportFactory,
} from "./EthereumClient";
import type { EthereumAsset } from "./EthereumAsset";
import type { EthereumAddress } from "./EvmCall";
import {
  getEthereumAssetBalance,
  type EthereumAssetBalance,
  type EthereumAssetBalanceError,
} from "./getEthereumAssetBalance";
import type { ConfiguredEthereumChain } from "./parseEthereumPortfolioConfig";

export type EthereumPortfolioAssetBalance =
  | {
    readonly status: "fulfilled";
    readonly symbol: string;
    readonly balance: EthereumAssetBalance;
  }
  | {
    readonly status: "failed";
    readonly symbol: string;
    readonly asset: EthereumAsset;
    readonly error: EthereumAssetBalanceError;
  };

export type EthereumPortfolioChainBalances =
  | {
    readonly status: "fulfilled";
    readonly chain: ConfiguredEthereumChain;
    readonly assets: readonly EthereumPortfolioAssetBalance[];
  }
  | {
    readonly status: "failed";
    readonly chain: ConfiguredEthereumChain;
    readonly error: EthereumClientCreationError;
  };

export async function getEthereumPortfolioBalances(
  chains: readonly ConfiguredEthereumChain[],
  address: EthereumAddress,
  createTransport: EvmCallTransportFactory,
): Promise<readonly EthereumPortfolioChainBalances[]> {
  return await Promise.all(
    chains.map(async (chain): Promise<EthereumPortfolioChainBalances> => {
      const client = EthereumClient.create(
        { chainId: chain.chainId, rpcUrl: chain.rpcUrl },
        createTransport,
      );
      if (!client.ok) {
        return { status: "failed", chain, error: client.error };
      }

      const assets: readonly {
        readonly symbol: string;
        readonly asset: EthereumAsset;
      }[] = [
        {
          symbol: chain.nativeSymbol,
          asset: { kind: "native-eth" },
        },
        ...chain.assets.map((asset) => ({
          symbol: asset.symbol,
          asset: {
            kind: "erc20" as const,
            tokenAddress: asset.address,
          },
        })),
      ];

      const balances = await Promise.all(
        assets.map(async ({ symbol, asset }): Promise<EthereumPortfolioAssetBalance> => {
          const balance = await getEthereumAssetBalance(
            client.value,
            address,
            asset,
          );
          return balance.ok
            ? { status: "fulfilled", symbol, balance: balance.value }
            : { status: "failed", symbol, asset, error: balance.error };
        }),
      );
      return { status: "fulfilled", chain, assets: balances };
    }),
  );
}
