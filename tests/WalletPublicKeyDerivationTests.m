/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/WalletPublicKeyDerivation.h"

#include <string.h>
#include <wally_bip32.h>
#include <wally_core.h>

@interface WalletPublicKeyDerivationTests : MacwltTestCase
@end

@implementation WalletPublicKeyDerivationTests

- (void)testPublicChildDerivationMatchesLibwally {
    NSData *seed = MacwltTestDataFromHex(@"000102030405060708090a0b0c0d0e0f");
    struct ext_key root;
    struct ext_key child;
    memset(&root, 0, sizeof(root));
    memset(&child, 0, sizeof(child));
    XCTAssertEqual(bip32_key_from_seed(seed.bytes, seed.length,
                                       BIP32_VER_MAIN_PRIVATE, 0, &root),
                   WALLY_OK);
    XCTAssertEqual(bip32_key_from_parent_path_str(&root,
                                                  "m/0/1",
                                                  0,
                                                  BIP32_FLAG_KEY_PUBLIC,
                                                  &child),
                   WALLY_OK);
    NSData *rootPublicKey = [NSData dataWithBytes:root.pub_key length:sizeof(root.pub_key)];
    NSData *chainCode = [NSData dataWithBytes:root.chain_code length:sizeof(root.chain_code)];
    NSError *error = nil;

    NSData *derived = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                                           chainCode:chainCode
                                                                      derivationPath:@"m/0/1"
                                                                               error:&error];

    NSData *expected = [NSData dataWithBytes:child.pub_key length:sizeof(child.pub_key)];
    XCTAssertNotNil(derived, @"wallet public derivation failed: %@", error);
    XCTAssertEqualObjects(derived, expected);
}

- (void)testHardenedPathReturnsUnsupportedHardenedPathError {
    NSData *rootPublicKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    NSData *chainCode = MacwltTestDataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );
    NSError *error = nil;

    NSData *derived = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                                           chainCode:chainCode
                                                                      derivationPath:@"m/84h/0/0"
                                                                               error:&error];

    XCTAssertNil(derived);
    XCTAssertEqualObjects(error.domain, WalletPublicKeyDerivationErrorDomain);
    XCTAssertEqual(error.code, WalletPublicKeyDerivationErrorUnsupportedHardenedPath);
}

@end
