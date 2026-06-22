/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "Address.h"

#include <CommonCrypto/CommonDigest.h>

#include "Bech32.h"
#include "RIPEMD160.h"

static const NSUInteger kCompressedPubKeyLen = 33;

NSString *p2wpkhAddress(NSData *compressedPubKey, BOOL mainnet) {
    if (compressedPubKey.length != kCompressedPubKeyLen) return nil;
    const uint8_t *pub = compressedPubKey.bytes;
    if (pub[0] != 0x02 && pub[0] != 0x03) return nil;

    uint8_t sha[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(pub, (CC_LONG)kCompressedPubKeyLen, sha);
    uint8_t hash160[RIPEMD160_DIGEST_LENGTH];
    ripemd160(sha, sizeof sha, hash160);

    char out[BECH32_MAX_LEN + 1];
    const char *hrp = mainnet ? "bc" : "tb";
    if (!segwitAddrEncode(out, hrp, 0, hash160, sizeof hash160)) return nil;

    return [NSString stringWithUTF8String:out];
}
