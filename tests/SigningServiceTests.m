/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "SigningService.h"
#import "SigningServiceProtocol.h"
#import "macwlt.h"

@interface SigningServiceTests : MacwltTestCase
@property (nonatomic, strong) SigningService *sut;
@end

@implementation SigningServiceTests

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.sut = [[SigningService alloc] initWithError:&error];
    XCTAssertNotNil(self.sut, @"SigningService init failed: %@", error);
}

- (void)tearDown {
    self.sut = nil;
    [super tearDown];
}

- (void)testUnsupportedSigningRepliesSynchronouslyWithUnavailableErrors {
    __block NSError *psbtError = nil;
    __block BOOL psbtReplied = NO;
    __block NSError *ethError = nil;
    __block BOOL ethReplied = NO;

    [self.sut signPSBT:[NSData dataWithBytes:"x" length:1]
             withReply:^(NSData *signedPSBT, NSError *error) {
        psbtReplied = YES;
        XCTAssertNil(signedPSBT);
        psbtError = error;
    }];
    [self.sut signEthTx:[NSData dataWithBytes:"x" length:1]
              withReply:^(NSData *signature, NSError *error) {
        ethReplied = YES;
        XCTAssertNil(signature);
        ethError = error;
    }];

    XCTAssertTrue(psbtReplied);
    XCTAssertEqualObjects(psbtError.domain, SigningServiceErrorDomain);
    XCTAssertEqual(psbtError.code, MACWLT_ERR_UNAVAILABLE);
    XCTAssertTrue(ethReplied);
    XCTAssertEqualObjects(ethError.domain, SigningServiceErrorDomain);
    XCTAssertEqual(ethError.code, MACWLT_ERR_UNAVAILABLE);
}

- (void)testPubkeyExportRepliesSynchronouslyWithUnsupportedAndUnavailableErrors {
    __block NSError *childError = nil;
    __block BOOL childReplied = NO;
    __block NSError *rootError = nil;
    __block BOOL rootReplied = NO;

    [self.sut exportPubkeyForDerivationPath:@"m/84h/0h/0h/0/0"
                                  withReply:^(NSData *publicKey, NSError *error) {
        childReplied = YES;
        XCTAssertNil(publicKey);
        childError = error;
    }];
    [self.sut exportPubkeyForDerivationPath:@"m"
                                  withReply:^(NSData *publicKey, NSError *error) {
        rootReplied = YES;
        XCTAssertNil(publicKey);
        rootError = error;
    }];

    XCTAssertTrue(childReplied);
    XCTAssertEqualObjects(childError.domain, SigningServiceErrorDomain);
    XCTAssertEqual(childError.code, MACWLT_ERR_UNSUPPORTED);
    XCTAssertTrue(rootReplied);
    XCTAssertEqualObjects(rootError.domain, SigningServiceErrorDomain);
    XCTAssertEqual(rootError.code, MACWLT_ERR_UNAVAILABLE);
}

- (void)testResetDeletesTheCurrentWalletWhenExplicitlyEnabled {
    XCTSkipUnless(MacwltTestWalletResetTestsEnabled(),
                  @"Set MACWLT_RUN_WALLET_RESET_TESTS=1 before launching the test run");
    __block BOOL reset = NO;
    __block NSError *resetError = nil;
    __block BOOL replied = NO;

    [self.sut resetWalletWithReply:^(BOOL didReset, NSError *error) {
        reset = didReset;
        resetError = error;
        replied = YES;
    }];

    XCTAssertTrue(replied);
    XCTAssertTrue(reset);
    XCTAssertNil(resetError);
}

@end
