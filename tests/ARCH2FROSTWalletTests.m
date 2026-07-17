/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "ARCH2FROSTWallet.h"

@interface ARCH2FROSTWalletTests : MacwltTestCase
@end

@implementation ARCH2FROSTWalletTests

- (void)testPersistenceRoundTripPreservesOnlyEnvelopesAndPublicMaterial {
    NSData *publicKeyA = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(2));
    NSData *publicKeyB = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(3));
    NSData *groupPublicKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    NSData *chainCode = MacwltTestDataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );
    ARCH2FROSTWallet *wallet =
        [[ARCH2FROSTWallet alloc] initWithEnvelopeA:[@"wrapped-a" dataUsingEncoding:NSUTF8StringEncoding]
                                          envelopeB:[@"wrapped-b" dataUsingEncoding:NSUTF8StringEncoding]
                               participantPublicKeyA:publicKeyA
                               participantPublicKeyB:publicKeyB
                                      groupPublicKey:groupPublicKey
                                           chainCode:chainCode];
    NSURL *url = MacwltTestTemporaryFileURL(@"arch2-wallet.plist");
    NSError *error = nil;

    XCTAssertTrue([wallet writeToURL:url error:&error], @"write failed: %@", error);
    ARCH2FROSTWallet *loaded = [ARCH2FROSTWallet loadFromURL:url error:&error];

    XCTAssertNotNil(loaded, @"load failed: %@", error);
    XCTAssertEqualObjects(loaded.envelopeA, wallet.envelopeA);
    XCTAssertEqualObjects(loaded.envelopeB, wallet.envelopeB);
    XCTAssertEqualObjects(loaded.participantPublicKeyA, publicKeyA);
    XCTAssertEqualObjects(loaded.participantPublicKeyB, publicKeyB);
    XCTAssertEqualObjects(loaded.groupPublicKey, groupPublicKey);
    XCTAssertEqualObjects(loaded.chainCode, chainCode);
}

- (void)testMissingRecordReturnsNotFoundErrorWithNullErrorAllowed {
    NSURL *url = MacwltTestTemporaryFileURL(@"missing-arch2-wallet.plist");

    ARCH2FROSTWallet *wallet = [ARCH2FROSTWallet loadFromURL:url error:NULL];

    XCTAssertNil(wallet);
}

@end
