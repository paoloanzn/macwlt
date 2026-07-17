<!--
 Copyright (c) 2026 macwlt contributors.
 SPDX-License-Identifier: Apache-2.0
-->

# macwlt

Self-custodial wallet infrastructure for macOS, backed by Secure Enclave signing.

macwlt keeps private-key operations on the local Mac and exposes a small native core,
an XPC signing service, a macOS app bundle, and a TypeScript CLI for wallet creation,
public-key/address export, and transaction signing.

## Repository

- `src/core/`: Objective-C wallet core, C ABI, signing, address derivation, and storage.
- `src/xpc/`: XPC signing service used to isolate signing operations.
- `src/ui/`: native macOS app entry point and wallet view controller.
- `cli/`: Bun/TypeScript command-line interface for the native library.
- `tests/`: XCTest coverage for the native core and signing boundaries.
- `vendor/`: native cryptography dependencies pulled in as submodules.

## Development

Install the macOS build dependencies:

```shell
brew bundle
```

Fetch vendored dependencies and build the native artifacts:

```shell
make submodules
make build
```

Run the native XCTest suite:

```shell
make test
```

Build and test the CLI:

```shell
cd cli
bun install
bun run build
bun test
```

## CLI

The CLI loads `./build/libmacwlt.dylib` by default. Set `MACWLT_LIB` to point at a
different native build.

```shell
MACWLT_LIB=../build/libmacwlt.dylib bun run dev -- create --json
MACWLT_LIB=../build/libmacwlt.dylib bun run dev -- address m/84'/0'/0'/0/0 --type bitcoin
MACWLT_LIB=../build/libmacwlt.dylib bun run dev -- sign-psbt --base64 <psbt>
```

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
