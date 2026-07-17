/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "Address.h"
#import "WalletAddressDerivation.h"
#import "WalletPublicKeyDerivation.h"

#include <string.h>
#include <wally_bip32.h>
#include <wally_core.h>

@interface WalletAddressDerivationTests : MacwltTestCase
@end

@implementation WalletAddressDerivationTests

- (void)testDerivedBitcoinAndEthereumAddressesMatchAddressHelpers {
    NSData *seed = MacwltTestDataFromHex(@"000102030405060708090a0b0c0d0e0f");
    struct ext_key root;
    memset(&root, 0, sizeof(root));
    XCTAssertEqual(bip32_key_from_seed(seed.bytes, seed.length,
                                       BIP32_VER_MAIN_PRIVATE, 0, &root),
                   WALLY_OK);
    NSData *rootPublicKey = [NSData dataWithBytes:root.pub_key length:sizeof(root.pub_key)];
    NSData *chainCode = [NSData dataWithBytes:root.chain_code length:sizeof(root.chain_code)];
    NSError *error = nil;
    NSData *derivedPublicKey =
        [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                             chainCode:chainCode
                                                        derivationPath:@"m/0/1"
                                                                 error:&error];
    NSString *bitcoinAddress =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m/0/1"
                                                       addressType:WalletAddressTypeBitcoinP2WPKHTestnet
                                                             error:&error];
    NSString *ethAddress =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m/0/1"
                                                       addressType:WalletAddressTypeEthereum
                                                             error:&error];

    XCTAssertNotNil(derivedPublicKey, @"wallet public derivation failed: %@", error);
    XCTAssertEqualObjects(bitcoinAddress, p2wpkhAddress(derivedPublicKey, NO));
    XCTAssertEqualObjects(ethAddress, ethereumAddress(derivedPublicKey));
}

- (void)testUnsupportedAddressTypeReturnsUnsupportedTypeError {
    NSData *rootPublicKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    NSData *chainCode = MacwltTestDataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );
    NSError *error = nil;

    NSString *address =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m"
                                                       addressType:(WalletAddressType)999
                                                             error:&error];

    XCTAssertNil(address);
    XCTAssertEqualObjects(error.domain, WalletAddressDerivationErrorDomain);
    XCTAssertEqual(error.code, WalletAddressDerivationErrorUnsupportedAddressType);
}

@end
