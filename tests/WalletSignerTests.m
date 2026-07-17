/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/HardenedBuffer.h"
#import "../src/core/HardenedShareWindow.h"
#import "../src/core/WalletShareEnvelope.h"
#import "../src/core/WalletSigner.h"
#import "../src/core/WalletSigningEngine.h"

#include <string.h>
#include <wally_core.h>
#include <wally_crypto.h>

static BOOL MacwltTestLoadShareData(HardenedBuffer *buffer,
                                    NSData *share,
                                    NSError **outError) {
    if (share.length > buffer.length) return NO;
    if (![buffer unmaskWithError:outError]) return NO;
    memcpy([buffer mutableBytes], share.bytes, share.length);
    return YES;
}

@interface TestWalletShareEnvelope : WalletShareEnvelope
@property (nonatomic, copy, readonly) NSData *testShareA;
@property (nonatomic, copy, readonly) NSData *testShareB;
@property (nonatomic, copy, readonly) NSArray<NSString *> *events;
- (instancetype)initWithShareA:(NSData *)shareA
                        shareB:(NSData *)shareB
                jointPublicKey:(NSData *)jointPublicKey NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                         envelopeB:(NSData *)envelopeB
          jointCompressedPublicKey:(NSData *)jointCompressedPublicKey
                          chainCode:(NSData *)chainCode NS_UNAVAILABLE;
@end

@implementation TestWalletShareEnvelope {
    NSMutableArray<NSString *> *_mutableEvents;
}

- (instancetype)initWithShareA:(NSData *)shareA
                        shareB:(NSData *)shareB
                jointPublicKey:(NSData *)jointPublicKey {
    self = [super initWithEnvelopeA:[NSData dataWithBytes:"a" length:1]
                          envelopeB:[NSData dataWithBytes:"b" length:1]
           jointCompressedPublicKey:jointPublicKey
                           chainCode:nil];
    if (self) {
        _testShareA = [shareA copy];
        _testShareB = [shareB copy];
        _mutableEvents = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSString *> *)events {
    return [_mutableEvents copy];
}

- (BOOL)performWithHardenedShareWindow:(HardenedShareWindow *)window
                              shareAUse:(HardenedShareWindowUseBlock)shareAUse
                              shareBUse:(HardenedShareWindowUseBlock)shareBUse
                                  error:(NSError **)outError {
    NSParameterAssert(window);
    return [window performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                 NSError **error) {
        [_mutableEvents addObject:@"loadA"];
        return MacwltTestLoadShareData(targetBuffer, self.testShareA, error);
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **error) {
        [_mutableEvents addObject:@"useA"];
        return shareAUse(shareBytes, shareLength, error);
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **error) {
        [_mutableEvents addObject:@"loadB"];
        return MacwltTestLoadShareData(targetBuffer, self.testShareB, error);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **error) {
        [_mutableEvents addObject:@"useB"];
        return shareBUse(shareBytes, shareLength, error);
    } error:outError];
}

@end

@interface WalletSignerTests : MacwltTestCase
@end

@implementation WalletSignerTests

- (void)testSplitSharesProduceVerifiableSignatureForEquivalentChildKey {
    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    NSData *tweak = MacwltTestScalarData(5);
    NSData *digest = MacwltTestDataFromHex(@"0102030405060708090a0b0c0d0e0f10"
                                           @"1112131415161718191a1b1c1d1e1f20");
    NSData *parentKey = MacwltTestPrivateKeyByMultiplying(shareA, shareB);
    NSData *childKey = MacwltTestPrivateKeyByAdding(parentKey, tweak);
    NSData *publicKey = MacwltTestCompressedPublicKeyForSecret(childKey);
    NSError *error = nil;

    WalletECDSASignature *signature = [WalletSigner signatureForDigest:digest
                                                                 shareA:shareA
                                                                 shareB:shareB
                                                                  tweak:tweak
                                                                  error:&error];

    XCTAssertNotNil(signature);
    XCTAssertEqual(signature.compactSignature.length, 64);
    XCTAssertGreaterThan(signature.derSignature.length, 0U);
    XCTAssertEqual((signature.recoveryID & ~3), 0);
    XCTAssertEqual(wally_ec_sig_verify(publicKey.bytes,
                                       publicKey.length,
                                       digest.bytes,
                                       digest.length,
                                       EC_FLAG_ECDSA,
                                       signature.compactSignature.bytes,
                                       signature.compactSignature.length),
                   WALLY_OK);
}

- (void)testShareEnvelopeSigningUsesHardenedShareWindowAndVerifies {
    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    NSData *tweak = MacwltTestScalarData(5);
    NSData *digest = MacwltTestDataFromHex(@"0102030405060708090a0b0c0d0e0f10"
                                           @"1112131415161718191a1b1c1d1e1f20");
    NSData *parentKey = MacwltTestPrivateKeyByMultiplying(shareA, shareB);
    NSData *childKey = MacwltTestPrivateKeyByAdding(parentKey, tweak);
    NSData *publicKey = MacwltTestCompressedPublicKeyForSecret(childKey);
    TestWalletShareEnvelope *shareEnvelope =
        [[TestWalletShareEnvelope alloc] initWithShareA:shareA
                                                 shareB:shareB
                                         jointPublicKey:MacwltTestCompressedPublicKeyForSecret(parentKey)];
    NSError *error = nil;

    WalletECDSASignature *signature = [WalletSigner signatureForDigest:digest
                                                         shareEnvelope:shareEnvelope
                                                                 tweak:tweak
                                                                 error:&error];

    XCTAssertNotNil(signature);
    XCTAssertEqualObjects(shareEnvelope.events, (@[@"loadA", @"useA", @"loadB", @"useB"]));
    XCTAssertEqual(wally_ec_sig_verify(publicKey.bytes,
                                       publicKey.length,
                                       digest.bytes,
                                       digest.length,
                                       EC_FLAG_ECDSA,
                                       signature.compactSignature.bytes,
                                       signature.compactSignature.length),
                   WALLY_OK);
}

- (void)testUnbootstrappedEngineReportsUnavailable {
    WalletSigner *engine = [[WalletSigner alloc] init];
    NSError *publicKeyError = nil;
    NSError *signatureError = nil;
    NSString *rootDerivationPath = [NSString stringWithUTF8String:"m"];

    NSData *publicKey = [engine publicKeyForDerivationPath:rootDerivationPath
                                                     error:&publicKeyError];
    NSData *signature = [engine ethereumSignatureForTransaction:[NSData dataWithBytes:"x" length:1]
                                                          error:&signatureError];

    XCTAssertTrue([engine conformsToProtocol:@protocol(WalletSigningEngine)]);
    XCTAssertNil(publicKey);
    XCTAssertEqualObjects(publicKeyError.domain, WalletSignerErrorDomain);
    XCTAssertEqual(publicKeyError.code, WalletSignerErrorUnavailable);
    XCTAssertNil(signature);
    XCTAssertEqualObjects(signatureError.domain, WalletSignerErrorDomain);
    XCTAssertEqual(signatureError.code, WalletSignerErrorUnavailable);
}

@end
