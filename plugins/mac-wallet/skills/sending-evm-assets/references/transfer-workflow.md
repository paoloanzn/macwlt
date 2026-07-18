# EVM Transfer Workflow

## 1. Locate macwlt

Prefer an installed command:

```shell
command -v macwlt
```

When working in the macwlt repository and no installed command exists, build
the CLI if needed and use the repository entry point:

```shell
pnpm --filter @macwlt/cli build
bun packages/cli/dist/main.js help
```

Represent the chosen invocation as `MACWLT` in the steps below. It may be the
single executable `macwlt` or the argument vector
`bun packages/cli/dist/main.js`. Do not flatten an argument vector into an
unquoted shell string.

## 2. Initialize The Config

macwlt creates its packaged default config before dispatching a command. If
`~/.config/macwlt/config.json` does not exist, run:

```shell
macwlt help
```

For the repository entry point, use:

```shell
bun packages/cli/dist/main.js help
```

Do not reset or replace an existing config.

## 3. Resolve The Request

Find this skill's directory from the loaded `SKILL.md` path. Run its resolver
with separate arguments:

```shell
node <skill-dir>/scripts/resolve-transfer.mjs \
  --amount 10 \
  --asset USDC \
  --chain Base \
  --recipient 0x0000000000000000000000000000000000000000
```

Use `--path <derivation-path>` only when the user supplied a path. Use
`--config <path>` only when operating with an explicitly selected HOME or test
config.

The resolver validates the amount and recipient, then resolves the chain ID and
asset contract from the config. It emits JSON containing:

- canonical chain and asset details;
- the configured token address;
- a token balance command;
- a native gas balance command;
- the final send command.

The command arrays begin with `macwlt`. If the repository entry point is being
used, replace only that first array item with
`bun packages/cli/dist/main.js`.

## 4. Check Balances

Run both read-only balance commands from the resolver. For an ERC-20 transfer:

- the token balance must be at least the requested amount;
- the native balance must be nonzero so the wallet can pay gas.

Use the `address` field returned by the balance JSON as the sender. Both balance
commands must resolve to the same sender. If they do not, stop.

Do not infer that a nonzero native balance is sufficient for a particular fee.
The send command estimates the transaction before signing and will reject
insufficient native funds when that check is supported.

## 5. Request Final Confirmation

Show exactly:

- sender address;
- amount and canonical asset symbol;
- network name and chain ID;
- token contract for ERC-20 transfers;
- recipient address;
- derivation path;
- token and native balances.

Then ask:

```text
Send <amount> <asset> on <network> (<chain-id>) from <sender> to <recipient>? [y/N]
```

Stop and wait. An empty response, `n`, `no`, an unrelated answer, or no response
means no. Do not execute the send command.

## 6. Submit Once

After a fresh `y` or `yes`, run the resolver's send command exactly once. Keep
`--json` enabled.

On success, report the transaction hash and say the transfer was submitted.
macwlt's current output proves broadcast submission, not on-chain confirmation.

If the command fails before returning a transaction hash, report the error. If
it may have broadcast but the result is unclear, state that the outcome is
unknown and do not retry automatically.
