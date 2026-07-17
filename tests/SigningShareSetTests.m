/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/SigningShareSet.h"

@interface SigningShareSetTests : MacwltTestCase
@end

@implementation SigningShareSetTests

- (void)testJointPublicKeyWithUnitShareMatchesOtherSharePublicKey {
    NSData *one = MacwltTestScalarData(1);
    NSData *two = MacwltTestScalarData(2);
    NSError *error = nil;

    NSData *joint = [SigningShareSet jointCompressedPublicKeyForShareA:one
                                                                shareB:two
                                                                 error:&error];

    XCTAssertNotNil(joint, @"joint public key failed: %@", error);
    XCTAssertEqualObjects(joint, MacwltTestCompressedPublicKeyForSecret(two));
}

- (void)testInvalidShareReturnsInvalidShareError {
    NSData *zero = MacwltTestScalarData(0);
    NSData *one = MacwltTestScalarData(1);
    NSError *error = nil;

    NSData *joint = [SigningShareSet jointCompressedPublicKeyForShareA:zero
                                                                shareB:one
                                                                 error:&error];

    XCTAssertNil(joint);
    XCTAssertEqualObjects(error.domain, SigningShareSetErrorDomain);
    XCTAssertEqual(error.code, SigningShareSetErrorInvalidShare);
}

- (void)testGeneratedSharesHaveCommutativeJointPublicKey {
    NSError *error = nil;

    SigningShareSet *shareSet = [SigningShareSet generateWithError:&error];
    XCTAssertNotNil(shareSet, @"share generation failed: %@", error);
    NSData *swapped = [SigningShareSet jointCompressedPublicKeyForShareA:shareSet.shareB
                                                                  shareB:shareSet.shareA
                                                                   error:&error];

    XCTAssertEqual(shareSet.shareA.length, 32);
    XCTAssertEqual(shareSet.shareB.length, 32);
    XCTAssertEqual(shareSet.jointCompressedPublicKey.length, 33);
    XCTAssertEqualObjects(swapped, shareSet.jointCompressedPublicKey);
}

@end
