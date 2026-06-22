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

#define BIP32_HARDENED 0x80000000u

typedef struct {
    uint8_t priv[32];
    uint8_t chainCode[32];
} ExtKey;

// Build the root node from seed bytes.
bool bip32MasterKey(const secp256k1_context *ctx,
                    const uint8_t *seed, size_t seedLen,
                    ExtKey *out);

// Derive a private child key. Returns false for degenerate BIP-32 cases.
bool bip32CKDPriv(const secp256k1_context *ctx,
                  const ExtKey *parent, uint32_t index,
                  ExtKey *out);

// Walk a path string such as "m/84'/0'/0'/0/0" from the seed-derived root.
bool bip32Derive(const secp256k1_context *ctx,
                 const uint8_t *seed, size_t seedLen,
                 const char *path,
                 ExtKey *out);

#endif /* MACWLT_BIP32_H */
