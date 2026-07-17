/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/hex.h"

#include <wally_bip39.h>
#include <wally_core.h>

@interface BIP39Tests : MacwltTestCase
@end

@implementation BIP39Tests

- (void)testMnemonicSeedMatchesKnownVector {
    NSArray<NSString *> *words = @[
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"about",
    ];
    NSString *mnemonic = [words componentsJoinedByString:@" "];
    uint8_t seedBytes[BIP39_SEED_LEN_512];
    int ret = bip39_mnemonic_to_seed512(mnemonic.UTF8String, "TREZOR",
                                        seedBytes, sizeof(seedBytes));
    NSData *seed = [NSData dataWithBytes:seedBytes length:sizeof(seedBytes)];
    NSString *expected =
        @"c55257c360c07c72029aebc1b53c05ed"
        @"0362ada38ead3e3e9efa3708e5349553"
        @"1f09a6987599d18264c1e1c92f2cf141"
        @"630c7a3c4ab7c81b2f001698e7463b04";

    XCTAssertEqual(ret, WALLY_OK);
    XCTAssertEqualObjects(hex(seed), expected);
}

@end
