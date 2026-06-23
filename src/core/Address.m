/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "Address.h"

#import <dispatch/dispatch.h>

#include <CommonCrypto/CommonDigest.h>
#include <openssl/evp.h>
#include <secp256k1.h>
#include <string.h>

#include "Bech32.h"
#include "RIPEMD160.h"

enum {
    kCompressedPubKeyLen = 33,
    kUncompressedPubKeyLen = 65,
    kEthereumRawPubKeyLen = 64,
    kEthereumAddressLen = 20,
    kKeccak256DigestLen = 32,
};

static const char kHexDigits[] = "0123456789abcdef";

static const EVP_MD *keccak256Digest(void) {
    static EVP_MD *digest = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        digest = EVP_MD_fetch(NULL, "KECCAK-256", NULL);
    });
    return digest;
}

static BOOL keccak256(const uint8_t *input, NSUInteger inputLen,
                      uint8_t out[kKeccak256DigestLen]) {
    const EVP_MD *digest = keccak256Digest();
    if (!digest) return NO;

    unsigned int outLen = 0;
    if (!EVP_Digest(input, inputLen, out, &outLen, digest, NULL)) return NO;
    return outLen == kKeccak256DigestLen;
}

static secp256k1_context *addressSecp256k1Context(void) {
    static secp256k1_context *ctx = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ctx = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY);
    });
    return ctx;
}

static BOOL ethereumUncompressedPublicKey(NSData *publicKey,
                                          uint8_t out[kUncompressedPubKeyLen]) {
    const NSUInteger publicKeyLen = publicKey.length;
    if (publicKeyLen != kCompressedPubKeyLen &&
        publicKeyLen != kUncompressedPubKeyLen &&
        publicKeyLen != kEthereumRawPubKeyLen) {
        return NO;
    }

    const uint8_t *input = publicKey.bytes;
    size_t inputLen = publicKeyLen;
    uint8_t prefixed[kUncompressedPubKeyLen];
    if (publicKeyLen == kEthereumRawPubKeyLen) {
        prefixed[0] = 0x04;
        memcpy(prefixed + 1, input, kEthereumRawPubKeyLen);
        input = prefixed;
        inputLen = kUncompressedPubKeyLen;
    }

    secp256k1_context *ctx = addressSecp256k1Context();
    if (!ctx) return NO;

    secp256k1_pubkey pubKey;
    if (!secp256k1_ec_pubkey_parse(ctx, &pubKey, input, inputLen)) return NO;

    size_t outLen = kUncompressedPubKeyLen;
    if (!secp256k1_ec_pubkey_serialize(ctx, out, &outLen, &pubKey,
                                       SECP256K1_EC_UNCOMPRESSED)) {
        return NO;
    }
    return outLen == kUncompressedPubKeyLen;
}

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

NSString *ethereumAddress(NSData *publicKey) {
    uint8_t uncompressed[kUncompressedPubKeyLen];
    if (!ethereumUncompressedPublicKey(publicKey, uncompressed)) return nil;

    uint8_t pubKeyHash[kKeccak256DigestLen];
    if (!keccak256(uncompressed + 1, kEthereumRawPubKeyLen, pubKeyHash)) return nil;
    const uint8_t *addressBytes = pubKeyHash + kKeccak256DigestLen - kEthereumAddressLen;

    char lowerHex[kEthereumAddressLen * 2 + 1];
    for (NSUInteger i = 0; i < kEthereumAddressLen; i++) {
        lowerHex[2 * i] = kHexDigits[addressBytes[i] >> 4];
        lowerHex[2 * i + 1] = kHexDigits[addressBytes[i] & 0x0f];
    }
    lowerHex[kEthereumAddressLen * 2] = '\0';

    uint8_t checksumHash[kKeccak256DigestLen];
    if (!keccak256((const uint8_t *)lowerHex, kEthereumAddressLen * 2, checksumHash)) return nil;

    char out[2 + kEthereumAddressLen * 2 + 1];
    out[0] = '0';
    out[1] = 'x';
    for (NSUInteger i = 0; i < kEthereumAddressLen * 2; i++) {
        char c = lowerHex[i];
        const uint8_t hashNibble = (i % 2 == 0)
            ? (checksumHash[i / 2] >> 4)
            : (checksumHash[i / 2] & 0x0f);
        if (c >= 'a' && c <= 'f' && hashNibble >= 8) c -= 'a' - 'A';
        out[2 + i] = c;
    }
    out[sizeof(out) - 1] = '\0';

    return [NSString stringWithUTF8String:out];
}
