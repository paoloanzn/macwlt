<!--
 Copyright (c) 2026 macwlt contributors.
 SPDX-License-Identifier: Apache-2.0
-->

<div>
    <img src="../../assets/macwlt-core-1200x630.png" />
</div>

# @macwlt/core

Native wallet and signing infrastructure for macOS.

`@macwlt/core` is a private pnpm workspace package. It contains the
Objective-C implementation, the public C ABI used by foreign-function
interfaces, and the client/server contract shared with the isolated XPC
signing service. It is not an npm-distributed JavaScript library and it does
not contain an application entry point.

The package is deliberately split into a small client library and a
security-sensitive service. Callers link the client; key storage, transaction
handling, and signing execute in the service.

## Requirements

- macOS and the macOS SDK;
- Xcode, including the XCTest runtime for native tests;
- Clang, Make, CMake, Autoconf, Automake, and Libtool;
- Rust and Cargo for the threshold ECDSA adapter;
- Node.js 20 or later and pnpm 10 or later for workspace scripts.

Wallet creation and signing use the Secure Enclave and may require biometric
authentication. The native unit tests use controlled test material where
hardware-backed state would make a test nondeterministic.

## Architecture

```text
CLI or native consumer
        │
        ▼
public C ABI ─────────────── packages/core/src/macwlt.h
        │
        ▼
SigningServiceClient
        │
        │  NSXPCConnection
        ▼
com.macwlt.SigningService.xpc
        │
        ├── WalletSigner                 legacy/P2WPKH Bitcoin
        ├── ARCH2FROSTSigningEngine      Taproot Bitcoin
        └── ARCH2ThresholdECDSASigningEngine
                                         Ethereum
```

The build produces distinct artifacts:

| Artifact | Purpose | Security-sensitive implementation |
| --- | --- | --- |
| `build/libmacwlt.dylib` | C ABI and XPC client transport | No signing engines or persisted shares |
| `build/com.macwlt.SigningService.xpc` | Sandboxed signing service | Wallet storage, derivation, and signing engines |
| `build/threshold-ecdsa/release/libmacwlt_threshold_ecdsa.a` | Narrow Rust/C protocol adapter | CGGMP24 key generation and signing |
| `build/MacwltCoreTests.xctest` | Native XCTest bundle | Core implementation plus test doubles and fixtures |

The service target is owned by [`@macwlt/xpc`](../xpc). Its production
entitlements disable network client and server access. The Objective-C
[`SigningServiceProtocol`](src/SigningServiceProtocol.h) is an internal process
boundary; [`macwlt.h`](src/macwlt.h) is the supported integration boundary for
external consumers.

### Signing engine routing

Routing is explicit and is part of the wallet compatibility contract:

| Operation | Objective-C owner | Cryptographic backend | Current scope |
| --- | --- | --- | --- |
| Wallet bootstrap, P2WPKH addresses, non-Taproot PSBTs | `WalletSigner` and `WalletSigningEngine` | libwally and secp256k1 | Legacy split wallet |
| P2TR addresses, `m/86...` public keys, Taproot PSBTs | `ARCH2FROST*` | Pinned and locally patched `secp256k1-frost` | Two-party FROST/Schnorr |
| Ethereum address and transaction signing | `ARCH2ThresholdECDSA*` | CGGMP24 through the Rust/C adapter | Two-party threshold ECDSA; root path `m` only |

Taproot PSBT content selects FROST. P2TR address types select FROST directly.
Ethereum address types select threshold ECDSA directly. A routing change can
therefore change the public key and address a caller observes; it must be
treated as a wallet migration, not as an internal refactor.

### Language and ownership boundaries

Objective-C owns the product behavior:

- wallet persistence and schema validation;
- Secure Enclave wrapper keys and biometric policy;
- hardened memory windows and cleanup;
- XPC request routing and concurrency;
- Ethereum recovery parity;
- public C ABI validation and error translation.

Rust is intentionally limited to
[`threshold-ecdsa`](threshold-ecdsa): a static adapter with three C operations
for generating participant state, signing an Ethereum preimage, and securely
freeing returned bytes. Rust types, serialized protocol messages, and Rust
errors do not cross that adapter boundary.

The CGGMP24 implementation is pinned as the
[`vendor/cggmp24`](../../vendor/cggmp24) Git submodule. Keep it in `vendor/`;
do not replace it with a registry dependency or a copied source tree.
[`Cargo.lock`](threshold-ecdsa/Cargo.lock) and the path dependency prevent
protocol crates from drifting across incompatible revisions.

## Security model

This package reduces exposure of signing material; it does not make the
signing-service process a hardware wallet.

- The XPC service is sandboxed and has no network client or server entitlement.
- Persisted participant state is encrypted with purpose-specific Secure
  Enclave wrapper keys. The secp256k1 signing shares themselves are not Secure
  Enclave keys.
- Modern wallet state uses a biometric policy tied to the current enrolled
  biometric set.
- Decrypted state is handled in locked, access-controlled memory and wiped
  before it is released. Cleanup paths must remain effective on errors and
  exceptions.
- `macwlt_reset_wallet` is destructive: it removes every supported wallet
  record and its managed Secure Enclave wrapper keys.

FROST and CGGMP24 avoid reconstructing a complete private scalar during their
protocols. In the current local deployment, however, both encrypted
participant states are unwrapped inside the same signing-service process for a
signing session. This protects against several storage and partial-compromise
failures, but it does not provide process or device isolation between
participants. That property would require a transport and independently
isolated participant processes.

Never log secrets, participant state, decrypted envelopes, transaction
preimages, authentication context, or raw `NSData` descriptions. New secret
lifetimes require an explicit cleanup path and tests for both success and
failure.

## Public C API

Include [`src/macwlt.h`](src/macwlt.h):

```c
#include "macwlt.h"

macwlt_wallet_t *wallet = NULL;
if (macwlt_wallet_create(&wallet) != MACWLT_SUCCESS) {
    /* No wallet handle was created. */
    return;
}

uint8_t joint_public_key[33];
size_t joint_public_key_length = sizeof(joint_public_key);
if (macwlt_bootstrap_wallet(wallet,
                            joint_public_key,
                            &joint_public_key_length) != MACWLT_SUCCESS) {
    macwlt_err_t code = macwlt_last_error(wallet);
    const char *message = macwlt_last_error_message(wallet);
    /* Copy message before another call on this wallet changes error state. */
    (void)code;
    (void)message;
}

macwlt_wallet_free(wallet);
```

### Lifetime and error rules

- `macwlt_wallet_create` creates an opaque handle and its service connection.
- Every successfully created handle must be released with
  `macwlt_wallet_free`; freeing `NULL` is safe.
- Calls return `MACWLT_SUCCESS` (`0`) or `MACWLT_FAILURE` (`-1`).
- After a failure on a valid handle, inspect `macwlt_last_error` and
  `macwlt_last_error_message` before issuing another call on that handle.
- Error message storage belongs to the wallet and must not be freed or retained
  after the next operation.
- Calls appear synchronous at the C boundary while their implementation crosses
  XPC. Do not invoke them from a thread that must remain responsive.

The stable error vocabulary is `macwlt_err_t`: invalid argument, service
unavailable, authentication required or failed, buffer too small, unsupported,
parse failure, signing failure, and internal failure. Objective-C implementation
errors must be translated into this vocabulary before crossing the C ABI.

### Output buffers

Binary and string outputs use an in/out length:

1. The caller supplies the buffer capacity in `*inout_length`.
2. If capacity is insufficient, the function returns
   `MACWLT_FAILURE`, sets `MACWLT_ERR_BUFFER_TOO_SMALL`, and writes the
   required capacity to `*inout_length`.
3. The caller resizes the buffer and retries.

Address capacities include the terminating NUL byte. Exported public keys and
the bootstrap key are compressed 33-byte secp256k1 public keys. Ethereum
signing returns 65 bytes in `r || s || yParity` form; the supplied preimage is
Keccak-256 hashed by the threshold adapter.

### Derivation and feature constraints

- Derivation paths must start at `m`.
- Hardened path components are rejected at the public C boundary.
- Public-key export routes `m/86...` to FROST and other paths to the legacy
  engine.
- Ethereum threshold ECDSA currently supports only the root path `m`.
- Attestation is reserved in the ABI but currently returns
  `MACWLT_ERR_UNSUPPORTED`.

## Objective-C engineering contract

[`CLAUDE.md`](CLAUDE.md) is the normative Objective-C guide for this package.
New code is expected to preserve these conventions:

- use `NS_ASSUME_NONNULL_BEGIN`/`END` and annotate real nullable values;
- use lightweight generics for Foundation collections;
- expose immutable state with `readonly`, use `copy` for externally supplied
  value objects, and designate initializers explicitly;
- make invalid initializers unavailable instead of leaving partially
  initialized objects possible;
- use `NS_ENUM` or `NS_OPTIONS` and keep switches exhaustive;
- use `NSParameterAssert` for programmer contract violations and `NSError` for
  expected runtime failures;
- preserve ARC ownership and Core Foundation bridging semantics;
- document thread-safety and serialize mutation of shared signing state;
- keep private declarations in class extensions and keep headers focused on
  the smallest useful public surface.

At the XPC boundary, reply exactly once on every path, pass property-list/XPC
safe values, and translate implementation errors without leaking internal or
secret data. At the Rust boundary, validate pointer/length pairs, prevent
panics from unwinding across C, copy returned data into Objective-C-owned
storage, and call the adapter's secure free function.

## Source map

| Path | Responsibility |
| --- | --- |
| [`src/macwlt.h`](src/macwlt.h), [`src/macwlt.m`](src/macwlt.m) | Public C ABI, opaque handle lifecycle, buffer and error conventions |
| [`src/SigningServiceProtocol.h`](src/SigningServiceProtocol.h) | Shared NSXPC contract |
| `src/SigningServiceClient.*` | Client connection and development-service transport |
| `src/SigningService.*` | Service routing, engine selection, and error mapping |
| `src/ARCH2FROST*` | FROST library loading, wallet state, derivation, and signing |
| `src/ARCH2ThresholdECDSA*` | Objective-C ownership of threshold ECDSA state and sessions |
| [`threshold-ecdsa`](threshold-ecdsa) | Narrow Rust/C CGGMP24 adapter |
| `src/Wallet*` | Legacy wallet envelopes, derivation, and signing |
| `src/Hardened*`, `src/SecureWipe.h` | Locked-memory and wipe primitives |
| `src/PSBT.*`, `src/Address.*` | Transaction parsing and address encoding |
| [`../../tests`](../../tests) | Repository-level native XCTest sources |

## Build

Run commands from the repository root. Initialize the pinned native
dependencies and install the workspace first:

```shell
make submodules
pnpm install
```

Build the client dynamic library only:

```shell
pnpm --filter @macwlt/core build
```

Build the complete native core, including the signing service:

```shell
make build
```

Useful native targets are:

| Command | Output |
| --- | --- |
| `make core` | `build/libmacwlt.dylib` |
| `make signing-service` | `build/com.macwlt.SigningService.xpc` |
| `make build` | Both client library and signing service |
| `pnpm build` | All workspace packages, in dependency order |

The root [`Makefile`](../../Makefile) is the source of truth for native compiler
flags, code signing, entitlements, dependency builds, and output locations.
Ad-hoc local signing is the default. Distribution builds must supply the
appropriate signing identity and entitlement-compatible packaging.

## Tests

Run the complete native XCTest suite:

```shell
pnpm --filter @macwlt/core test
```

The equivalent native command is:

```shell
make test
```

Run one XCTest class or selector during development:

```shell
make test FILTER=ARCH2ThresholdECDSATests
```

Tests compile the Objective-C implementation with warnings as errors and cover
the C ABI, addresses, PSBT behavior, wallet envelopes, hardened memory,
FROST, threshold ECDSA, routing, reset behavior, and service integration.
Security-sensitive changes should add regression coverage for corrupted state,
cleanup failures, and repeated/concurrent operations where applicable.

## Native dependency policy

Cryptographic implementations are pinned repository submodules:

| Dependency | Role |
| --- | --- |
| [`vendor/libwally-core`](../../vendor/libwally-core) | Bitcoin primitives, PSBTs, and legacy secp256k1 operations |
| [`vendor/secp256k1-frost`](../../vendor/secp256k1-frost) | FROST and BIP-340 operations |
| [`vendor/XKCP`](../../vendor/XKCP) | Keccak primitives |
| [`vendor/cggmp24`](../../vendor/cggmp24) | Threshold ECDSA protocol implementation |

The FROST dependency is copied into `build/` and hardened with
[`patches/secp256k1-frost-secret-memory.patch`](../../patches/secp256k1-frost-secret-memory.patch)
before compilation. Never edit the submodule to simulate the patch, and never
silently drop or fuzz-apply it.

Dependency revisions, patches, Cargo locks, headers, and linked binaries form
one reviewed unit. A cryptographic dependency update must include its submodule
revision, any required patch update, a locked rebuild, and the relevant native
tests.

## Change checklist

Before merging a core change, verify the applicable items:

- C ABI additions preserve opaque ownership, buffer sizing, and stable error
  semantics.
- XPC protocol changes are implemented by both client and service and reply on
  every path.
- A new wallet record is included in reset and migration behavior.
- Address export and signing use the same engine and public key.
- Secret material has bounded lifetime, deterministic cleanup, and no logging.
- Objective-C headers preserve nullability, generics, ownership, and designated
  initializer contracts.
- Rust remains behind the narrow C adapter; CGGMP24 remains a pinned
  `vendor/` Git submodule.
- The native build succeeds and focused plus full XCTest coverage passes.

## License

Apache-2.0. See the repository [LICENSE](../../LICENSE) and
[NOTICE](../../NOTICE).
