/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2ThresholdECDSALibrary.h"

#import "SecureWipe.h"
#import "ThresholdECDSA.h"

#include <string.h>

NSString * const ARCH2ThresholdECDSALibraryErrorDomain =
    @"macwlt.ARCH2ThresholdECDSALibrary";

static const NSUInteger kGroupPublicKeyLength = 33;
static const NSUInteger kCompactSignatureLength = 64;
static const NSUInteger kErrorBufferLength = 1024;

static NSError *libraryError(ARCH2ThresholdECDSALibraryErrorCode code,
                             NSString *message) {
    return [NSError errorWithDomain:ARCH2ThresholdECDSALibraryErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setLibraryError(NSError **outError,
                            ARCH2ThresholdECDSALibraryErrorCode code,
                            const char *message,
                            NSString *fallback) {
    if (!outError) return;
    NSString *description = message && message[0] != '\0'
        ? [NSString stringWithUTF8String:message] : fallback;
    *outError = libraryError(code, description ?: fallback);
}

@implementation ARCH2ThresholdECDSAKeyMaterial

- (instancetype)initWithParticipantA:(NSMutableData *)participantA
                        participantB:(NSMutableData *)participantB
                      groupPublicKey:(NSData *)groupPublicKey {
    NSParameterAssert(participantA.length > 0);
    NSParameterAssert(participantB.length > 0);
    NSParameterAssert(groupPublicKey.length == kGroupPublicKeyLength);
    self = [super init];
    if (self) {
        _participantA = participantA;
        _participantB = participantB;
        _groupPublicKey = [groupPublicKey copy];
    }
    return self;
}

@end

@implementation ARCH2ThresholdECDSALibrary

+ (instancetype)library {
    return [[self alloc] init];
}

- (nullable ARCH2ThresholdECDSAKeyMaterial *)
    generateKeyMaterialWithError:(NSError **)outError {
    uint8_t *participantA = NULL;
    uint8_t *participantB = NULL;
    size_t participantALength = 0;
    size_t participantBLength = 0;
    uint8_t groupPublicKey[kGroupPublicKeyLength];
    char errorBuffer[kErrorBufferLength];
    memset(groupPublicKey, 0, sizeof(groupPublicKey));
    memset(errorBuffer, 0, sizeof(errorBuffer));

    int result = macwlt_threshold_ecdsa_generate(&participantA,
                                                 &participantALength,
                                                 &participantB,
                                                 &participantBLength,
                                                 groupPublicKey,
                                                 errorBuffer,
                                                 sizeof(errorBuffer));
    if (result != 0) {
        setLibraryError(outError,
                        ARCH2ThresholdECDSALibraryErrorGenerationFailed,
                        errorBuffer,
                        @"Threshold ECDSA key generation failed");
        return nil;
    }
    if (!participantA || !participantB ||
        participantALength == 0 || participantBLength == 0) {
        macwlt_threshold_ecdsa_free(participantA, participantALength);
        macwlt_threshold_ecdsa_free(participantB, participantBLength);
        setLibraryError(outError,
                        ARCH2ThresholdECDSALibraryErrorInvalidOutput,
                        NULL,
                        @"Threshold ECDSA generated invalid participant state");
        return nil;
    }

    NSMutableData *dataA = [NSMutableData dataWithBytes:participantA
                                                 length:participantALength];
    NSMutableData *dataB = [NSMutableData dataWithBytes:participantB
                                                 length:participantBLength];
    macwlt_threshold_ecdsa_free(participantA, participantALength);
    macwlt_threshold_ecdsa_free(participantB, participantBLength);
    NSData *publicKey = [NSData dataWithBytes:groupPublicKey
                                      length:sizeof(groupPublicKey)];
    secureWipe(groupPublicKey, sizeof(groupPublicKey));
    return [[ARCH2ThresholdECDSAKeyMaterial alloc]
        initWithParticipantA:dataA
                participantB:dataB
              groupPublicKey:publicKey];
}

- (nullable NSData *)signTransaction:(NSData *)transaction
                        participantA:(NSData *)participantA
                        participantB:(NSData *)participantB
                               error:(NSError **)outError {
    if (transaction.length == 0 ||
        participantA.length == 0 ||
        participantB.length == 0) {
        setLibraryError(outError,
                        ARCH2ThresholdECDSALibraryErrorSigningFailed,
                        NULL,
                        @"Threshold ECDSA signing input must not be empty");
        return nil;
    }

    uint8_t signature[kCompactSignatureLength];
    char errorBuffer[kErrorBufferLength];
    memset(signature, 0, sizeof(signature));
    memset(errorBuffer, 0, sizeof(errorBuffer));
    int result = macwlt_threshold_ecdsa_sign_transaction(
        participantA.bytes,
        participantA.length,
        participantB.bytes,
        participantB.length,
        transaction.bytes,
        transaction.length,
        signature,
        errorBuffer,
        sizeof(errorBuffer)
    );
    if (result != 0) {
        secureWipe(signature, sizeof(signature));
        setLibraryError(outError,
                        ARCH2ThresholdECDSALibraryErrorSigningFailed,
                        errorBuffer,
                        @"Threshold ECDSA signing failed");
        return nil;
    }
    NSData *output = [NSData dataWithBytes:signature length:sizeof(signature)];
    secureWipe(signature, sizeof(signature));
    return output;
}

@end
