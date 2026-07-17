<!--
 Copyright (c) 2026 macwlt contributors.
 SPDX-License-Identifier: Apache-2.0
-->

# `@macwlt/core`

Native wallet core for macwlt. This package contains the Objective-C implementation,
the C ABI used by foreign-function interfaces, and the client/server types shared
with its isolated XPC signing service.

This is a private pnpm workspace package, not an npm-distributed JavaScript library.
Its package scripts delegate native builds and tests to the repository
[Makefile](../../Makefile).

## Responsibilities

- Expose a C-compatible wallet API through [`src/macwlt.h`](src/macwlt.h).
- Send wallet and signing requests across the `com.macwlt.SigningService` boundary.
- Implement wallet bootstrapping, key derivation, address generation, PSBT handling,
  Ethereum transaction signing, and FROST signing.
- Keep key material in Secure Enclave-backed storage and hardened memory structures.
- Provide the native types used by [`@macwlt/xpc`](../xpc) and
  [`@macwlt/cli`](../cli).

The package does not contain an application entry point. The signing-service
executable and its entitlements belong to `@macwlt/xpc`.

## Architecture

```text
CLI / native consumer
          │
          ▼
      C ABI (macwlt.h)
          │
          ▼
 SigningServiceClient
          │
     XPC boundary
          │
          ▼
   SigningService
          │
 wallet, FROST, PSBT, and key engines
```

The standalone `libmacwlt.dylib` contains the C ABI and signing-service client.
Sensitive operations are performed by the separately built XPC service. Development
builds can locate the service bundle under `build/`.

## Source layout

- `src/macwlt.h` and `src/macwlt.m`: stable C/FFI boundary and error model.
- `src/SigningServiceProtocol.h`: shared XPC contract.
- `src/SigningServiceClient.*`: client-side XPC and development-service transport.
- `src/SigningService.*`: signing-service implementation.
- `src/ARCH2FROST*`: FROST library loading, wallet state, and signing engine.
- `src/Wallet*`: wallet storage, derivation, envelopes, and signing orchestration.
- `src/Hardened*` and `src/SecureWipe.h`: protected-memory primitives.
- `src/PSBT.*` and `src/Address.*`: transaction and address functionality.

Native XCTest sources intentionally remain in the repository-level
[`tests/`](../../tests) directory.

## Build

From the repository root, initialize dependencies and install the pnpm workspace:

```shell
make submodules
pnpm install
```

Build only the client dynamic library:

```shell
pnpm --filter @macwlt/core build
```

This produces `build/libmacwlt.dylib`. To also build the XPC signing service, CLI,
documentation, and landing site, run:

```shell
pnpm build
```

## Test

Run the native XCTest suite through the package script:

```shell
pnpm --filter @macwlt/core test
```

The script invokes the root Make target and produces
`build/MacwltCoreTests.xctest`.

## C API conventions

Include [`src/macwlt.h`](src/macwlt.h) when integrating through C or an FFI:

```c
#include "macwlt.h"

macwlt_wallet_t *wallet = NULL;
if (macwlt_wallet_create(&wallet) != MACWLT_SUCCESS) {
    /* Handle allocation failure. */
}

/* Use the wallet handle. */

macwlt_wallet_free(wallet);
```

API calls return `MACWLT_SUCCESS` or `MACWLT_FAILURE`. After a failure, inspect
`macwlt_last_error()` and `macwlt_last_error_message()` on the same wallet handle.
Functions with output buffers use an in/out length pointer; when capacity is
insufficient, the required size is returned and the wallet error is
`MACWLT_ERR_BUFFER_TOO_SMALL`.

The C header declares operations for:

- wallet creation, reset, bootstrap, and destruction;
- public-key and Bitcoin/Ethereum address export;
- PSBT and Ethereum transaction signing;
- attestation export.

## Dependencies

Native cryptographic dependencies are repository submodules under `vendor/`:

- `libwally-core`;
- `secp256k1-frost`, with the repository hardening patch applied at build time;
- XKCP for Keccak functionality.

The implementation also uses macOS Foundation and Security frameworks. It is
macOS-specific and requires the Apple SDK and code-signing tools used by the root
Makefile.

## License

Apache-2.0. See the repository [LICENSE](../../LICENSE) and
[NOTICE](../../NOTICE).
