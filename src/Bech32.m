/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include "Bech32.h"

#include <string.h>

// The 32 Bech32 symbols, indexed by 5-bit value.
static const char *kCharset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

// One step of the BIP-173 checksum: a GF(2) polynomial mod the generator. `pre`
// carries the running 30-bit remainder; the top 5 bits select which generator
// coefficients to fold back in.
static uint32_t polymodStep(uint32_t pre) {
    uint8_t b = (uint8_t)(pre >> 25);
    return ((pre & 0x1FFFFFFu) << 5) ^
           (uint32_t)(-((b >> 0) & 1) & 0x3b6a57b2u) ^
           (uint32_t)(-((b >> 1) & 1) & 0x26508e6du) ^
           (uint32_t)(-((b >> 2) & 1) & 0x1ea119fau) ^
           (uint32_t)(-((b >> 3) & 1) & 0x3d4233ddu) ^
           (uint32_t)(-((b >> 4) & 1) & 0x2a1462b3u);
}

// Encode hrp + data (5-bit symbols) + 6-symbol checksum into `out`. `data` holds
// `dataLen` values each < 32. Returns false if a value is out of range or the
// result would exceed the 90-char Bech32 limit.
static bool bech32Encode(char *out, const char *hrp,
                         const uint8_t *data, size_t dataLen) {
    size_t hrpLen = strlen(hrp);
    if (hrpLen + 1 + dataLen + 6 > BECH32_MAX_LEN) return false;

    // Fold the HRP into the checksum: high bits, separator, then low bits.
    uint32_t chk = 1;
    for (size_t i = 0; i < hrpLen; i++) {
        chk = polymodStep(chk) ^ ((uint8_t)hrp[i] >> 5);
    }
    chk = polymodStep(chk);
    for (size_t i = 0; i < hrpLen; i++) {
        chk = polymodStep(chk) ^ ((uint8_t)hrp[i] & 0x1f);
    }

    char *p = out;
    for (size_t i = 0; i < hrpLen; i++) *p++ = hrp[i];
    *p++ = '1';

    for (size_t i = 0; i < dataLen; i++) {
        if (data[i] >> 5) return false;
        chk = polymodStep(chk) ^ data[i];
        *p++ = kCharset[data[i]];
    }

    // Six zero symbols flush the data through, then XOR the constant (1 for
    // Bech32) and emit the checksum symbols most-significant first.
    for (int i = 0; i < 6; i++) chk = polymodStep(chk);
    chk ^= 1;
    for (int i = 0; i < 6; i++) {
        *p++ = kCharset[(chk >> ((5 - i) * 5)) & 0x1f];
    }
    *p = '\0';
    return true;
}

// Regroup `in` (bytes, inLen) from 8-bit to 5-bit symbols, appending to `out`
// from offset `*outLen`. Pads the final symbol with zero bits (pad == true for
// encoding). Returns false only if a symbol overflows, which cannot happen here.
static bool convertBits(uint8_t *out, size_t *outLen,
                        const uint8_t *in, size_t inLen) {
    uint32_t acc = 0;
    int bits = 0;
    for (size_t i = 0; i < inLen; i++) {
        acc = (acc << 8) | in[i];
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            out[(*outLen)++] = (acc >> bits) & 0x1f;
        }
    }
    if (bits > 0) {
        out[(*outLen)++] = (acc << (5 - bits)) & 0x1f;
    }
    return true;
}

bool segwitAddrEncode(char *out, const char *hrp,
                      int witver, const uint8_t *program, size_t programLen) {
    if (!out || !hrp || !program) return false;
    if (witver < 0 || witver > 16) return false;
    if (programLen < 2 || programLen > 40) return false;
    // Witness v0 is defined only for 20-byte (P2WPKH) and 32-byte (P2WSH).
    if (witver == 0 && programLen != 20 && programLen != 32) return false;

    // First data symbol is the witness version; the rest is the 5-bit program.
    uint8_t data[1 + 65];
    data[0] = (uint8_t)witver;
    size_t dataLen = 1;
    convertBits(data, &dataLen, program, programLen);

    return bech32Encode(out, hrp, data, dataLen);
}
