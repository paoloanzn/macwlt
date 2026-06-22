/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_BECH32_H
#define MACWLT_BECH32_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Bech32 / native SegWit address encoding (BIP-173).
//
// A short, self-contained C routine: the witness program is regrouped from
// 8-bit to 5-bit symbols, prefixed with the witness version, and emitted as
// "<hrp>1<data><6-char checksum>". Witness version 0 (P2WPKH / P2WSH) uses the
// original Bech32 checksum constant (1); later versions would use Bech32m, which
// this wallet does not need.

// BIP-173 caps a Bech32 string at 90 characters; +1 for the NUL terminator.
#define BECH32_MAX_LEN 90

// Encode a SegWit address into `out` (must hold at least BECH32_MAX_LEN + 1
// bytes). `hrp` is the human-readable prefix ("bc" mainnet, "tb" testnet),
// `witver` the witness version (0..16), and `program`/`programLen` the witness
// program (20 bytes for P2WPKH, 32 for P2WSH). Writes a NUL-terminated lowercase
// string and returns true; returns false on any out-of-range argument.
bool segwitAddrEncode(char *out, const char *hrp,
                      int witver, const uint8_t *program, size_t programLen);

#endif /* MACWLT_BECH32_H */
