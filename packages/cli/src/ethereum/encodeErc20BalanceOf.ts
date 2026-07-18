import { encodeFunctionData, type Hex } from "viem";
import type { EthereumAddress } from "./EvmCall";

const balanceOfAbi = [{
  type: "function",
  name: "balanceOf",
  stateMutability: "view",
  inputs: [{ name: "account", type: "address" }],
  outputs: [{ name: "", type: "uint256" }],
}] as const;

export function encodeErc20BalanceOf(account: EthereumAddress): Hex {
  return encodeFunctionData({
    abi: balanceOfAbi,
    functionName: "balanceOf",
    args: [account],
  });
}
