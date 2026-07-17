/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "Address.h"

#import <dispatch/dispatch.h>

#include <KeccakHash.h>
#include <secp256k1.h>
#include <string.h>
#include <wally_address.h>
#include <wally_core.h>
#include <wally_crypto.h>
#include <wally_script.h>

enum {
    kCompressedPubKeyLen = 33,
    kUncompressedPubKeyLen = 65,
    kEthereumRawPubKeyLen = 64,
    kEthereumAddressLen = 20,
    kKeccak256DigestLen = 32,
};

static const char kHexDigits[] = "0123456789abcdef";

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
}

static BOOL keccak256(const uint8_t *input, NSUInteger inputLen,
                      uint8_t out[kKeccak256DigestLen]) {
    if (inputLen > SIZE_MAX / 8) return NO;

    Keccak_HashInstance hash;
    if (Keccak_HashInitialize(&hash, 1088, 512, 256, 0x01) != KECCAK_SUCCESS) {
        return NO;
    }
    if (Keccak_HashUpdate(&hash, input, inputLen * 8) != KECCAK_SUCCESS) return NO;
    return Keccak_HashFinal(&hash, out) == KECCAK_SUCCESS;
}

static secp256k1_context *addressSecp256k1Context(void) {
    if (!ensureWallyInitialized()) return NULL;
    return wally_get_secp_context();
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

    if (!ensureWallyInitialized()) return nil;

    uint8_t hash160[HASH160_LEN];
    if (wally_hash160(pub, kCompressedPubKeyLen, hash160, sizeof(hash160)) != WALLY_OK) {
        return nil;
    }

    uint8_t witnessProgram[2 + HASH160_LEN] = {0x00, HASH160_LEN};
    memcpy(witnessProgram + 2, hash160, sizeof(hash160));
    const char *hrp = mainnet ? "bc" : "tb";
    char *out = NULL;
    if (wally_addr_segwit_from_bytes(witnessProgram, sizeof(witnessProgram),
                                     hrp, 0, &out) != WALLY_OK) {
        return nil;
    }

    NSString *address = [NSString stringWithUTF8String:out];
    wally_free_string(out);
    return address;
}

NSString *p2trAddress(NSData *compressedInternalPublicKey, BOOL mainnet) {
    if (compressedInternalPublicKey.length != EC_PUBLIC_KEY_LEN) return nil;
    if (!ensureWallyInitialized()) return nil;

    uint8_t outputPublicKey[EC_PUBLIC_KEY_LEN];
    if (wally_ec_public_key_bip341_tweak(compressedInternalPublicKey.bytes,
                                         compressedInternalPublicKey.length,
                                         NULL,
                                         0,
                                         0,
                                         outputPublicKey,
                                         sizeof(outputPublicKey)) != WALLY_OK) {
        return nil;
    }

    uint8_t script[WALLY_SCRIPTPUBKEY_P2TR_LEN];
    size_t written = 0;
    if (wally_scriptpubkey_p2tr_from_bytes(outputPublicKey + 1,
                                           EC_XONLY_PUBLIC_KEY_LEN,
                                           0,
                                           script,
                                           sizeof(script),
                                           &written) != WALLY_OK ||
        written != sizeof(script)) {
        return nil;
    }

    char *out = NULL;
    const char *hrp = mainnet ? "bc" : "tb";
    if (wally_addr_segwit_from_bytes(script, sizeof(script),
                                     hrp, 0, &out) != WALLY_OK ||
        !out) {
        return nil;
    }
    NSString *address = [NSString stringWithUTF8String:out];
    wally_free_string(out);
    return address;
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
