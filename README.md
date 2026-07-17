<!--
 Copyright (c) 2026 macwlt contributors.
 SPDX-License-Identifier: Apache-2.0
-->

# macwlt

Self-custodial wallet infrastructure for macOS, backed by Secure Enclave signing.

macwlt keeps private-key operations on the local Mac and exposes a small native core,
an XPC signing service, and a TypeScript CLI for wallet creation, public-key/address
export, and transaction signing.

## Repository

- `packages/core/`: Objective-C wallet core, C ABI, signing, address derivation, and storage.
- `packages/xpc/`: XPC signing service used to isolate signing operations.
- `packages/cli/`: TypeScript command-line interface and Bun FFI adapter.
- `apps/docs/`: VitePress documentation site.
- `apps/landing/`: React landing site.
- `tests/`: XCTest coverage for the native core and signing boundaries.
- `vendor/`: native cryptography dependencies pulled in as submodules.

The three product packages and two web apps are pnpm workspace members. Native
packages keep their Objective-C sources in `src/` and expose Make-backed workspace
scripts; the CLI uses pnpm for dependency management and Bun as its runtime.

## Development

Install Node.js 20 or newer, pnpm 10 or newer, and Bun 1.2 or newer. Then install
the macOS native build dependencies:

```shell
brew bundle
```

Fetch vendored dependencies, install workspace dependencies, and build everything:

```shell
make submodules
pnpm install
pnpm build
```

Run the native XCTest and CLI unit suites:

```shell
pnpm test
```

Package-scoped commands use pnpm filters:

```shell
pnpm --filter @macwlt/core build
pnpm --filter @macwlt/cli typecheck
pnpm --filter @macwlt/cli test
```

## CLI

The CLI loads `./build/libmacwlt.dylib` by default. Set `MACWLT_LIB` to point at a
different native build.

```shell
pnpm dev -- create --json
pnpm dev -- address m/84'/0'/0'/0/0 --type bitcoin
pnpm dev -- sign-psbt --base64 <psbt>
```

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
