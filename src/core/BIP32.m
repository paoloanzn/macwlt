/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include "BIP32.h"
#include "SecureWipe.h"

#include <string.h>

#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>

static const char kMasterKey[] = "Bitcoin seed";

static void secureClear(void *ptr, size_t len) {
    secureWipe(ptr, len);
}

static void ser32(uint32_t value, uint8_t out[4]) {
    out[0] = (uint8_t)(value >> 24);
    out[1] = (uint8_t)(value >> 16);
    out[2] = (uint8_t)(value >> 8);
    out[3] = (uint8_t)value;
}

bool bip32MasterKey(const secp256k1_context *ctx,
                    const uint8_t *seed, size_t seedLen,
                    ExtKey *out) {
    if (!ctx || !seed || !out) return false;

    uint8_t I[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, kMasterKey, strlen(kMasterKey), seed, seedLen, I);

    if (!secp256k1_ec_seckey_verify(ctx, I)) {
        secureClear(I, sizeof I);
        return false;
    }

    memcpy(out->priv, I, 32);
    memcpy(out->chainCode, I + 32, 32);
    secureClear(I, sizeof I);
    return true;
}

bool bip32CKDPriv(const secp256k1_context *ctx,
                  const ExtKey *parent, uint32_t index,
                  ExtKey *out) {
    if (!ctx || !parent || !out) return false;

    uint8_t data[37];
    if (index >= BIP32_HARDENED) {
        data[0] = 0x00;
        memcpy(data + 1, parent->priv, 32);
    } else {
        secp256k1_pubkey pub;
        if (!secp256k1_ec_pubkey_create(ctx, &pub, parent->priv)) {
            secureClear(data, sizeof data);
            return false;
        }
        size_t pubLen = 33;
        secp256k1_ec_pubkey_serialize(ctx, data, &pubLen, &pub,
                                      SECP256K1_EC_COMPRESSED);
    }
    ser32(index, data + 33);

    uint8_t I[CC_SHA512_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA512, parent->chainCode, 32, data, sizeof data, I);
    secureClear(data, sizeof data);

    // child priv = parent priv + IL (mod n). seckey_tweak_add rejects the
    // degenerate cases (IL >= n, or the sum landing on zero) by returning 0.
    uint8_t child[32];
    memcpy(child, parent->priv, 32);
    int ok = secp256k1_ec_seckey_tweak_add(ctx, child, I);
    if (ok) {
        memcpy(out->priv, child, 32);
        memcpy(out->chainCode, I + 32, 32);
    }

    secureClear(child, sizeof child);
    secureClear(I, sizeof I);
    return ok != 0;
}

// Consume a hardened marker at `*p`, advancing past it. Accepts an ASCII
// apostrophe, "h"/"H", or the Unicode right single quote (’, UTF-8 e2 80 99).
static bool consumeHardenedMarker(const char **p) {
    const char *s = *p;
    if (*s == '\'' || *s == 'h' || *s == 'H') {
        *p = s + 1;
        return true;
    }
    if ((uint8_t)s[0] == 0xE2 && (uint8_t)s[1] == 0x80 && (uint8_t)s[2] == 0x99) {
        *p = s + 3;
        return true;
    }
    return false;
}

bool bip32Derive(const secp256k1_context *ctx,
                 const uint8_t *seed, size_t seedLen,
                 const char *path,
                 ExtKey *out) {
    if (!path || !out) return false;

    ExtKey node;
    if (!bip32MasterKey(ctx, seed, seedLen, &node)) return false;

    const char *p = path;
    if (*p != 'm' && *p != 'M') return false;
    p++;

    bool ok = true;
    while (ok && *p) {
        if (*p != '/') { ok = false; break; }
        p++;

        if (*p < '0' || *p > '9') { ok = false; break; }
        uint32_t index = 0;
        while (*p >= '0' && *p <= '9') {
            index = index * 10 + (uint32_t)(*p - '0');
            if (index >= BIP32_HARDENED) { ok = false; break; }
            p++;
        }
        if (!ok) break;

        if (consumeHardenedMarker(&p)) index |= BIP32_HARDENED;

        ExtKey child;
        ok = bip32CKDPriv(ctx, &node, index, &child);
        if (ok) node = child;
        secureClear(&child, sizeof child);
    }

    if (ok) *out = node;
    secureClear(&node, sizeof node);
    return ok;
}
