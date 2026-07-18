/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "ARCH2ThresholdECDSALibrary.h"
#import "ARCH2ThresholdECDSASigningEngine.h"
#import "ARCH2ThresholdECDSAWallet.h"
#import "HardenedBuffer.h"
#import "SecureWipe.h"

#import <secp256k1.h>
#import <secp256k1_recovery.h>

#include <KeccakHash.h>
#include <string.h>
#include <wally_core.h>

@interface ARCH2ThresholdECDSATestWallet : ARCH2ThresholdECDSAWallet

@property (nonatomic, strong) NSData *plainParticipantA;
@property (nonatomic, strong) NSData *plainParticipantB;

- (instancetype)initWithKeyMaterial:(ARCH2ThresholdECDSAKeyMaterial *)material;

@end

@implementation ARCH2ThresholdECDSATestWallet

- (instancetype)initWithKeyMaterial:(ARCH2ThresholdECDSAKeyMaterial *)material {
    self = [super initWithEnvelopeA:[@"test-a" dataUsingEncoding:NSUTF8StringEncoding]
                         envelopeB:[@"test-b" dataUsingEncoding:NSUTF8StringEncoding]
                participantALength:material.participantA.length
                participantBLength:material.participantB.length
                    groupPublicKey:material.groupPublicKey];
    if (self) {
        _plainParticipantA = material.participantA;
        _plainParticipantB = material.participantB;
    }
    return self;
}

- (BOOL)unwrapParticipant:(ARCH2ThresholdECDSAParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError **)outError {
    NSData *plain = participant == ARCH2ThresholdECDSAParticipantA
        ? self.plainParticipantA : self.plainParticipantB;
    if (plain.length != buffer.length || ![buffer unmaskWithError:outError]) return NO;
    memcpy(buffer.mutableBytes, plain.bytes, plain.length);
    return YES;
}

@end

static NSData *MacwltTestKeccak256(NSData *message) {
    Keccak_HashInstance hash;
    unsigned char digest[32] = {0};
    XCTAssertEqual(Keccak_HashInitialize(&hash, 1088, 512, 256, 0x01),
                   KECCAK_SUCCESS);
    XCTAssertEqual(Keccak_HashUpdate(&hash, message.bytes, message.length * 8),
                   KECCAK_SUCCESS);
    XCTAssertEqual(Keccak_HashFinal(&hash, digest), KECCAK_SUCCESS);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSData *MacwltTestRecoverEthereumPublicKey(NSData *signature,
                                                  NSData *transaction) {
    if (signature.length != 65) return nil;
    const unsigned char *bytes = signature.bytes;
    if (bytes[64] > 1) return nil;

    secp256k1_context *context = wally_get_secp_context();
    NSData *digest = MacwltTestKeccak256(transaction);
    secp256k1_ecdsa_recoverable_signature recoverable;
    secp256k1_pubkey publicKey;
    if (!secp256k1_ecdsa_recoverable_signature_parse_compact(
            context, &recoverable, bytes, bytes[64]) ||
        !secp256k1_ecdsa_recover(context,
                                 &publicKey,
                                 &recoverable,
                                 digest.bytes)) {
        return nil;
    }

    unsigned char compressed[33] = {0};
    size_t compressedLength = sizeof(compressed);
    if (!secp256k1_ec_pubkey_serialize(context,
                                       compressed,
                                       &compressedLength,
                                       &publicKey,
                                       SECP256K1_EC_COMPRESSED)) {
        return nil;
    }
    return [NSData dataWithBytes:compressed length:compressedLength];
}

@interface ARCH2ThresholdECDSATests : MacwltTestCase
@end

@implementation ARCH2ThresholdECDSATests

- (void)testGeneratedParticipantsProduceRecoverableEthereumSignature {
    ARCH2ThresholdECDSALibrary *library = [ARCH2ThresholdECDSALibrary library];
    NSError *error = nil;
    ARCH2ThresholdECDSAKeyMaterial *material =
        [library generateKeyMaterialWithError:&error];
    XCTAssertNotNil(material, @"threshold key generation failed: %@", error);
    if (!material) return;

    @try {
        ARCH2ThresholdECDSATestWallet *wallet =
            [[ARCH2ThresholdECDSATestWallet alloc] initWithKeyMaterial:material];
        ARCH2ThresholdECDSASigningEngine *engine =
            [[ARCH2ThresholdECDSASigningEngine alloc] initWithLibrary:library
                                                              wallet:wallet];
        NSData *transaction =
            [@"macwlt threshold ECDSA test transaction"
                dataUsingEncoding:NSUTF8StringEncoding];

        NSData *signature =
            [engine ethereumSignatureForTransaction:transaction error:&error];

        XCTAssertNotNil(signature, @"threshold signing failed: %@", error);
        XCTAssertEqual(signature.length, 65);
        XCTAssertEqualObjects(MacwltTestRecoverEthereumPublicKey(signature, transaction),
                              material.groupPublicKey);
    } @finally {
        secureWipe(material.participantA.mutableBytes, material.participantA.length);
        secureWipe(material.participantB.mutableBytes, material.participantB.length);
    }
}

- (void)testWalletPersistenceContainsEncryptedParticipantsAndPublicKey {
    NSData *groupPublicKey =
        MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(7));
    ARCH2ThresholdECDSAWallet *wallet =
        [[ARCH2ThresholdECDSAWallet alloc]
            initWithEnvelopeA:[@"wrapped-threshold-a"
                dataUsingEncoding:NSUTF8StringEncoding]
                     envelopeB:[@"wrapped-threshold-b"
                dataUsingEncoding:NSUTF8StringEncoding]
            participantALength:1234
            participantBLength:5678
                groupPublicKey:groupPublicKey];
    NSURL *url = MacwltTestTemporaryFileURL(@"threshold-ecdsa-wallet.plist");
    NSError *error = nil;

    XCTAssertTrue([wallet writeToURL:url error:&error], @"write failed: %@", error);
    ARCH2ThresholdECDSAWallet *loaded =
        [ARCH2ThresholdECDSAWallet loadFromURL:url error:&error];

    XCTAssertNotNil(loaded, @"load failed: %@", error);
    XCTAssertEqualObjects(loaded.envelopeA, wallet.envelopeA);
    XCTAssertEqualObjects(loaded.envelopeB, wallet.envelopeB);
    XCTAssertEqual(loaded.participantALength, 1234);
    XCTAssertEqual(loaded.participantBLength, 5678);
    XCTAssertEqualObjects(loaded.groupPublicKey, groupPublicKey);
}

@end
