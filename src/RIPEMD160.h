/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_RIPEMD160_H
#define MACWLT_RIPEMD160_H

#include <stddef.h>
#include <stdint.h>

// RIPEMD-160 (Dobbertin–Bosselaers–Preneel).
//
// CommonCrypto ships SHA-2 but not RIPEMD-160, so the second half of Bitcoin's
// HASH160 needs its own implementation. This is a small, self-contained C
// routine in the spirit of the project's other crypto primitives.

#define RIPEMD160_DIGEST_LENGTH 20

// Compute the 20-byte RIPEMD-160 digest of `data` into `out`.
void ripemd160(const uint8_t *data, size_t len,
               uint8_t out[RIPEMD160_DIGEST_LENGTH]);

#endif /* MACWLT_RIPEMD160_H */
