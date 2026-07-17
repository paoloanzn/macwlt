import { encodeFunctionData, type Hex } from "viem";
import type { EthereumAddress } from "./EvmCall";

const transferAbi = [{
  type: "function",
  name: "transfer",
  stateMutability: "nonpayable",
  inputs: [
    { name: "to", type: "address" },
    { name: "amount", type: "uint256" },
  ],
  outputs: [{ name: "", type: "bool" }],
}] as const;

export function encodeErc20Transfer(
  recipient: EthereumAddress,
  amount: bigint,
): Hex {
  return encodeFunctionData({
    abi: transferAbi,
    functionName: "transfer",
    args: [recipient, amount],
  });
}
