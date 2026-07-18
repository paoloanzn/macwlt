<div>
    <img src="../../assets/macwlt-cli-1200x630.png" />
</div>

# @macwlt/cli

TypeScript CLI for the macwlt native core.

## Install

The npm package currently supports Apple silicon Macs and requires Bun 1.2 or
newer:

```shell
npm i -g @macwlt/cli
macwlt help
```

The package includes `libmacwlt.dylib`, the signing-service XPC bundle, and the
signing service's native dependency. `MACWLT_LIB` can still override the bundled
library path for development.

## Commands

| Command | Usage |
| --- | --- |
| `create` | `macwlt create [--reset] [--json]` |
| `reset` | `macwlt reset --yes [--json]` |
| `reset-config` | `macwlt reset-config [--json]` |
| `pubkey` | `macwlt pubkey [path] [--json]` |
| `address` | `macwlt address [path] --type bitcoin\|bitcoin-testnet\|bitcoin-taproot\|bitcoin-taproot-testnet\|ethereum [--json]` |
| `balance` | `macwlt balance [--path <derivation-path>] [--json]` |
| `sign-eth` | `macwlt sign-eth --hex <typed-transaction-preimage-hex> [--json]` |
| `sign-psbt` | `macwlt sign-psbt --base64 <psbt> [--format base64\|hex] [--json]` |
| `send` | `macwlt send <amount> <token-address\|ETH> <chain-id> <recipient> [--rpc <url>] [--path <derivation-path>] [--json]` |
| `help` | `macwlt help` |
| `version` | `macwlt version` |
