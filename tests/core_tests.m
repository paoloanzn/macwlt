/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "../src/core/Address.h"
#import "../src/core/PSBT.h"
#import "../src/core/SigningServiceProtocol.h"
#import "../src/core/hex.h"

#include "../src/core/macwlt.h"
#include <wally_bip39.h>
#include <wally_core.h>

static void fail(NSString *message) {
    NSLog(@"%@", message);
    exit(1);
}

static void expect(BOOL condition, NSString *message) {
    if (!condition) fail(message);
}

static NSData *dataFromHex(NSString *string) {
    NSMutableData *data = [NSMutableData dataWithCapacity:string.length / 2];
    for (NSUInteger i = 0; i + 1 < string.length; i += 2) {
        NSString *byteString = [string substringWithRange:NSMakeRange(i, 2)];
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        expect([scanner scanHexInt:&byte],
               [NSString stringWithFormat:@"invalid hex byte %@", byteString]);
        uint8_t value = (uint8_t)byte;
        [data appendBytes:&value length:sizeof(value)];
    }
    return data;
}

static void testHex(void) {
    const uint8_t bytes[] = {0x00, 0xab, 0xff};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    expect([hex(data) isEqualToString:@"00abff"], @"hex encoding failed");
}

static void testBIP39MnemonicSeed(void) {
    NSArray<NSString *> *words = @[
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"about",
    ];
    NSString *mnemonic = [words componentsJoinedByString:@" "];
    uint8_t seedBytes[BIP39_SEED_LEN_512];
    int ret = bip39_mnemonic_to_seed512(mnemonic.UTF8String, "TREZOR",
                                        seedBytes, sizeof(seedBytes));
    NSData *seed = ret == WALLY_OK ? [NSData dataWithBytes:seedBytes
                                                     length:sizeof(seedBytes)] : nil;
    NSString *expected =
        @"c55257c360c07c72029aebc1b53c05ed"
        @"0362ada38ead3e3e9efa3708e5349553"
        @"1f09a6987599d18264c1e1c92f2cf141"
        @"630c7a3c4ab7c81b2f001698e7463b04";
    expect(seed != nil, @"BIP-39 seed derivation returned nil");
    expect([hex(seed) isEqualToString:expected], @"BIP-39 seed vector failed");
}

static void testP2WPKHAddress(void) {
    NSData *compressedPublicKey = dataFromHex(
        @"0279be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
    );
    NSString *address = p2wpkhAddress(compressedPublicKey, YES);
    expect([address isEqualToString:@"bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"],
           [NSString stringWithFormat:@"P2WPKH address vector failed: %@", address]);
}

static void testEthereumAddress(void) {
    NSData *generatorPublicKey = dataFromHex(
        @"79be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
        @"483ada7726a3c4655da4fbfc0e1108a8"
        @"fd17b448a68554199c47d08ffb10d4b8"
    );
    NSString *address = ethereumAddress(generatorPublicKey);
    expect([address isEqualToString:@"0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"],
           @"Ethereum address vector failed");
}

static void testPSBTInvalidData(void) {
    NSError *error = nil;
    PSBT *psbt = [PSBT psbtWithData:[@"not a psbt" dataUsingEncoding:NSUTF8StringEncoding]
                              error:&error];
    expect(psbt == nil, @"invalid PSBT data unexpectedly parsed");
    expect(error != nil, @"invalid PSBT data did not set NSError");
}

static void testSigningBoundaryHeaders(void) {
    macwlt_wallet_t *wallet = NULL;
    macwlt_err_t err = MACWLT_OK;
    expect(wallet == NULL, @"opaque wallet handle should compile as an incomplete type");
    expect(err == MACWLT_OK, @"C ABI error enum should expose MACWLT_OK");
    expect(MACWLT_FAILURE < MACWLT_SUCCESS, @"C ABI should use int status returns");
    expect(@protocol(SigningServiceProtocol) != nil,
           @"SigningServiceProtocol should be visible to Objective-C callers");
}

int main(void) {
    @autoreleasepool {
        expect(wally_init(0) == WALLY_OK, @"wally_init failed");
        testHex();
        testBIP39MnemonicSeed();
        testP2WPKHAddress();
        testEthereumAddress();
        testPSBTInvalidData();
        testSigningBoundaryHeaders();
        NSLog(@"core tests passed");
    }
    return 0;
}
