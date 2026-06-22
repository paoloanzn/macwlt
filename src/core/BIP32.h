/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_BIP32_H
#define MACWLT_BIP32_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <secp256k1.h>

// BIP-32 hierarchical deterministic key derivation.
//
// An ExtKey pairs a 32-byte private scalar with a 32-byte chain code; that pair
// is the canonical representation of a BIP-32 node. The HMAC-SHA512 hashing is
// pure C (CommonCrypto); only the modular addition of the child tweak to the
// parent scalar — and the point multiplication needed to serialize a parent
// public key for non-hardened steps — delegates to libsecp256k1.

#define BIP32_HARDENED 0x80000000u

typedef struct {
    uint8_t priv[32];
    uint8_t chainCode[32];
} ExtKey;

// Build the root node from a seed:
//   I = HMAC-SHA512("Bitcoin seed", seed)
// The left 32 bytes become the master private key, the right 32 the chain code.
// Returns false if the seed yields an invalid master key (IL == 0 or IL >= n),
// which happens with negligible probability.
bool bip32MasterKey(const secp256k1_context *ctx,
                    const uint8_t *seed, size_t seedLen,
                    ExtKey *out);

// Derive the child node of `parent` at `index`. Indices >= BIP32_HARDENED are
// hardened: the HMAC input is 0x00 || parent priv || ser32(index), binding the
// child to the parent private key. Otherwise the input is ser_compressed(parent
// pub) || ser32(index). Returns false if the result is degenerate (sum is zero
// or >= n); per BIP-32 the caller should proceed to the next index.
bool bip32CKDPriv(const secp256k1_context *ctx,
                  const ExtKey *parent, uint32_t index,
                  ExtKey *out);

// Walk a path string such as "m/84'/0'/0'/0/0" from the seed-derived root. A
// trailing apostrophe ('), "h"/"H", or the Unicode right single quote (’) marks
// a hardened index. Returns false on a malformed path or a derivation failure.
bool bip32Derive(const secp256k1_context *ctx,
                 const uint8_t *seed, size_t seedLen,
                 const char *path,
                 ExtKey *out);

#endif /* MACWLT_BIP32_H */
