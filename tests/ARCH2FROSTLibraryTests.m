/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/ARCH2FROSTLibrary.h"

@interface ARCH2FROSTLibraryTests : MacwltTestCase
@end

@implementation ARCH2FROSTLibraryTests

- (void)testDefaultLibraryLoadsHardenedNonceInitializer {
    NSError *poison = [NSError errorWithDomain:@"test.poison" code:1 userInfo:nil];
    NSError *error = poison;

    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];

    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    XCTAssertNotEqual(library.context, NULL);
    XCTAssertEqualObjects(error, poison);
}

- (void)testCallerOwnedNonceInitializerWritesCommitmentWithoutHeapNonceAPI {
    NSError *error = nil;
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];
    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    if (!library) return;

    NSData *secret = MacwltTestScalarData(2);
    NSData *publicKey = MacwltTestCompressedPublicKeyForSecret(secret);
    NSData *groupPublicKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    secp256k1_frost_keypair keypair;
    secp256k1_frost_nonce nonce;
    unsigned char bindingSeed[32] = {1};
    unsigned char hidingSeed[32] = {2};
    memset(&keypair, 0, sizeof(keypair));
    memset(&nonce, 0, sizeof(nonce));
    memcpy(keypair.secret, secret.bytes, secret.length);
    XCTAssertTrue([library loadPublicKey:&keypair.public_keys
                                  index:1
                       participantCount:2
                participantPublicKey33:publicKey.bytes
                     groupPublicKey33:groupPublicKey.bytes]);

    BOOL initialized = [library initializeNonce:&nonce
                                        keypair:&keypair
                                    bindingSeed:bindingSeed
                                     hidingSeed:hidingSeed];

    XCTAssertTrue(initialized);
    XCTAssertEqual(nonce.used, 0);
    XCTAssertEqual(nonce.commitments.index, 1U);
    XCTAssertNotEqual(memcmp(nonce.hiding, (unsigned char[32]){0}, 32), 0);
    XCTAssertNotEqual(memcmp(nonce.binding, (unsigned char[32]){0}, 32), 0);
}

@end
