---
name: sending-evm-assets
description: Resolve, preview, and send configured native or ERC-20 assets with the macwlt CLI on EVM networks. Use when a user asks to send or transfer assets such as USDC, USDT, WETH, or ETH on Base, Ethereum, Arbitrum, OP Mainnet, Polygon, BNB Smart Chain, or Avalanche.
license: Apache-2.0
metadata:
  author: macwlt contributors
  version: 1.0.0
  category: finance
  tags:
    - macwlt
    - wallet
    - evm
    - erc20
---

# Sending EVM Assets

Use this skill to turn a request such as "Send 10 USDC on Base to
`0x...`" into one reviewed `macwlt send` invocation.

## Safety Rules

- Use only the `macwlt` CLI for wallet access, signing, and broadcasting.
- Never request, read, print, export, or copy a seed phrase or private key.
- Resolve the network and asset from the user's macwlt config. Never guess a
  chain ID or token contract.
- Treat the original request as intent, not final approval. After resolving all
  values and checking balances, show the exact transfer summary and ask for a
  fresh `y/N` confirmation. Only `y` or `yes` approves it.
- Do not broadcast in the same turn in which confirmation is requested. Wait
  for the user's answer.
- Execute the resolved send command exactly once. If the result is ambiguous
  after signing or broadcasting, do not retry automatically.
- Never change the amount, recipient, chain, asset, token contract, derivation
  path, or RPC between confirmation and execution.

## Workflow

Read [references/transfer-workflow.md](references/transfer-workflow.md) and
follow it in order:

1. Locate a working `macwlt` command.
2. Initialize and read `~/.config/macwlt/config.json`.
3. Run `scripts/resolve-transfer.mjs` from this skill directory with the
   requested amount, asset, network, and recipient.
4. Use the resolver's read-only balance commands to verify the token balance
   and native gas balance.
5. Present the resolved transfer summary and wait for explicit confirmation.
6. Run the resolver's send command once with `--json`.
7. Report the transaction hash as submitted, not confirmed.

If any step fails, stop before broadcasting. Use
[references/troubleshooting.md](references/troubleshooting.md) for recovery.
