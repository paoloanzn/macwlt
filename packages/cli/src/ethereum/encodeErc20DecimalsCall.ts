import { encodeFunctionData, type Hex } from "viem";

const decimalsAbi = [{
  type: "function",
  name: "decimals",
  stateMutability: "view",
  inputs: [],
  outputs: [{ name: "", type: "uint8" }],
}] as const;

export function encodeErc20DecimalsCall(): Hex {
  return encodeFunctionData({
    abi: decimalsAbi,
    functionName: "decimals",
  });
}
