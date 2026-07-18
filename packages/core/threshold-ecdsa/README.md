# Threshold ECDSA protocol adapter

This package is the narrow protocol boundary used by macwlt's Objective-C
`ARCH2ThresholdECDSA*` classes. It builds a static library and exposes only
three C functions: generate two participant states, sign an Ethereum
transaction preimage, and securely release returned bytes.

Wallet persistence, Secure Enclave envelope keys, biometric policy, hardened
memory, Ethereum recovery parity, session serialization, and `NSError`
translation remain in Objective-C. Rust types and protocol messages do not
cross the adapter boundary.

The protocol implementation is
[`cggmp24`](https://github.com/LFDT-Lockness/cggmp21), whose implementation was
audited by Kudelski. The implementation and its companion protocol crates live
in the pinned `vendor/cggmp24` Git submodule. `Cargo.toml` uses that workspace
path, so Cargo cannot combine protocol crates from different pre-release
revisions.

This is a local two-participant deployment. CGGMP24 never reconstructs the
ECDSA private scalar, but both encrypted participant states are unwrapped
inside the signing-service process for an interactive signing session.
Process isolation between participants would require a separate transport and
participant processes; the Objective-C boundary is deliberately shaped so
that transport can be introduced without changing callers.
