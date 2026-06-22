/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "mnemonics.h"
#include <Foundation/Foundation.h>
#include <stdint.h>
#include <zlib.h>
#import <Security/Security.h>
#import "hex.h"

enum {
    kBIP39WordCount = 2048,
};

// Embed BIP-39 compressed list in the final binary.
static const uint8_t kCompressedWordlist[] = {
#include "../build/bip39_wordlist.inc"
};

static NSArray<NSString *> *gWordlist;

static uint32_t compressedWordlistDecodedLength(void) {
    size_t n = sizeof(kCompressedWordlist);
    if (n < 4) return 0;

    return ((uint32_t)kCompressedWordlist[n - 4]) |
        ((uint32_t)kCompressedWordlist[n - 3] << 8) |
        ((uint32_t)kCompressedWordlist[n - 2] << 16) |
        ((uint32_t)kCompressedWordlist[n - 1] << 24);
}

static NSArray<NSString *> *loadWordlist(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        uint32_t decodedLength = compressedWordlistDecodedLength();
        if (!decodedLength) return;

        NSMutableData *decoded = [NSMutableData dataWithLength:decodedLength];
        z_stream stream = {0};
        stream.next_in = (Bytef *)kCompressedWordlist;
        stream.avail_in = (uInt)sizeof(kCompressedWordlist);
        stream.next_out = (Bytef *)decoded.mutableBytes;
        stream.avail_out = (uInt)decoded.length;

        int rc = inflateInit2(&stream, 16 + MAX_WBITS);
        if (rc != Z_OK) return;

        rc = inflate(&stream, Z_FINISH);
        inflateEnd(&stream);
        if (rc != Z_STREAM_END || stream.total_out != decodedLength) return;

        NSString *text = [[NSString alloc]
            initWithData:decoded
                encoding:NSUTF8StringEncoding];
        if (!text) return;

        NSMutableArray<NSString *> *words =
            [NSMutableArray arrayWithCapacity:kBIP39WordCount];
        [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            (void)stop;
            if (line.length) [words addObject:line];
        }];
        if (words.count != kBIP39WordCount) return;

        gWordlist = [words copy];
    });

    return gWordlist;
}

static NSArray<NSString *> *generateMnemonic(int entropyBits) {
    NSArray<NSString *> *wordlist = loadWordlist();
    if (!wordlist) return nil;

    int entropyBytes = entropyBits / 8;
    uint8_t entropy[32];
    (void)SecRandomCopyBytes(kSecRandomDefault, entropyBytes, entropy);

    uint8_t hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(entropy, entropyBytes, hash);

    int csLen = entropyBytes / 32; int totBits = entropyBits + csLen;
    int wordCount = totBits / 11;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:wordCount];

    // Log(n * m)
    for (int w = 0; w < wordCount; w++) {
        int idx = 0;
        for (int b = 0; b < 11; b++ ) {
            int bitIndex = w * 11 + b;
            const uint8_t *source = entropy;
            int sourceBitIndex = bitIndex;
            if (bitIndex >= entropyBits) {
                source = hash;
                sourceBitIndex = bitIndex - entropyBits;
            }
            int byte = sourceBitIndex / 8;
            int bit = 7 - (sourceBitIndex % 8);
            int v = (source[byte] >> bit) & 1;
            idx = (idx << 1) | v;
        }
        [out addObject:wordlist[idx]];
    }
    return out;
}

static NSData *mnemonicToSeed(NSArray<NSString *> *words, NSString *passphrase) {
    NSString *passStr = [[words componentsJoinedByString:@" "]
        decomposedStringWithCompatibilityMapping];
    NSString *saltStr = [[NSString stringWithFormat:@"mnemonic%@", passphrase ?: @""]
        decomposedStringWithCompatibilityMapping];
    NSData *pass = [passStr dataUsingEncoding:NSUTF8StringEncoding];
    NSData *salt = [saltStr dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t out[64];
    int rc = CCKeyDerivationPBKDF(kCCPBKDF2,
        pass.bytes, pass.length,
            salt.bytes, salt.length,
            kCCPRFHmacAlgSHA512, 2048,
            out, sizeof(out));
    if (rc != kCCSuccess) return nil;
    return [NSData dataWithBytes:out length:sizeof(out)];
}
