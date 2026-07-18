# EVM Transfer Troubleshooting

## macwlt Is Not Found

When inside the macwlt repository:

```shell
pnpm --filter @macwlt/cli build
bun packages/cli/dist/main.js help
```

Outside the repository, stop and ask the user for the installed macwlt
executable or repository path. Do not replace macwlt with another wallet.

## Config Is Missing

Run `macwlt help` once to let macwlt create its packaged default at
`~/.config/macwlt/config.json`. Do not create a hand-written replacement and do
not reset an existing config.

## Network Or Asset Is Unknown

List the available chain names, chain IDs, native symbols, and ERC-20 symbols
from the config. Ask the user to select one or update the config. Never choose a
same-symbol contract from another chain.

## Balance Is Too Low

Stop before calling `macwlt send`. Report the available token amount and native
gas balance without proposing that the agent acquire, bridge, or swap funds
unless the user separately asks for that work.

## The Native Library Is Missing

When inside the repository, build the native library using the repository's
documented build steps. Otherwise ask the user for the correct `MACWLT_LIB`
path. Never work around the native library by exporting wallet secrets.

## User Declines Or Does Not Confirm

Do not run the send command. State that the transfer was not submitted.

## Broadcast Result Is Ambiguous

Do not retry. A second submission can create a second transfer. Report any
transaction hash or error output that exists and state that the outcome needs
independent chain verification.
