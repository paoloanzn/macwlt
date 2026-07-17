/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/WalletShareEnvelope.h"

@interface WalletShareEnvelopeTests : MacwltTestCase
@end

@implementation WalletShareEnvelopeTests

- (void)testPersistenceRoundTripPreservesEnvelopeAndRestrictsPermissions {
    NSData *envelopeA = [NSData dataWithBytes:"wrapped-a" length:9];
    NSData *envelopeB = [NSData dataWithBytes:"wrapped-b" length:9];
    NSData *jointPublicKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    NSData *chainCode = MacwltTestDataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );
    WalletShareEnvelope *envelope =
        [[WalletShareEnvelope alloc] initWithEnvelopeA:envelopeA
                                            envelopeB:envelopeB
                             jointCompressedPublicKey:jointPublicKey
                                            chainCode:chainCode];
    NSURL *url = MacwltTestTemporaryFileURL(@"wallet-share-envelope.plist");
    NSError *error = nil;

    XCTAssertTrue([envelope writeToURL:url error:&error],
                  @"wallet envelope write failed: %@", error);
    WalletShareEnvelope *loaded = [WalletShareEnvelope loadFromURL:url error:&error];
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&error];
    NSNumber *permissions = attributes[NSFilePosixPermissions];

    XCTAssertNotNil(loaded, @"wallet envelope load failed: %@", error);
    XCTAssertEqualObjects(loaded.envelopeA, envelopeA);
    XCTAssertEqualObjects(loaded.envelopeB, envelopeB);
    XCTAssertEqualObjects(loaded.jointCompressedPublicKey, jointPublicKey);
    XCTAssertEqualObjects(loaded.chainCode, chainCode);
    XCTAssertNotNil(attributes, @"could not read wallet envelope attributes: %@", error);
    XCTAssertEqual((permissions.unsignedShortValue & 0777), 0600);
}

- (void)testInvalidPersistentEnvelopeReturnsInvalidPersistentEnvelopeError {
    NSDictionary<NSString *, id> *propertyList = @{
        @"version": @1,
        @"envelopeA": [NSData dataWithBytes:"wrapped-a" length:9],
        @"envelopeB": [NSData dataWithBytes:"wrapped-b" length:9],
        @"jointCompressedPublicKey": [NSData dataWithBytes:"bad" length:3],
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    NSURL *url = MacwltTestTemporaryFileURL(@"invalid-wallet-share-envelope.plist");
    XCTAssertNotNil(data, @"test plist serialization failed: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error],
                  @"test directory creation failed: %@", error);
    XCTAssertTrue([data writeToURL:url options:NSDataWritingAtomic error:&error],
                  @"test plist write failed: %@", error);

    WalletShareEnvelope *loaded = [WalletShareEnvelope loadFromURL:url error:&error];

    XCTAssertNil(loaded);
    XCTAssertEqualObjects(error.domain, WalletShareEnvelopeErrorDomain);
    XCTAssertEqual(error.code, WalletShareEnvelopeErrorInvalidPersistentEnvelope);
}

@end
