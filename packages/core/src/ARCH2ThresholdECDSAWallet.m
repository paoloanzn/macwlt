/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2ThresholdECDSAWallet.h"

#import "ARCH2ThresholdECDSALibrary.h"
#import "HardenedBuffer.h"
#import "SEKeyManager.h"
#import "SecureWipe.h"
#import "WalletEnvelopeManager.h"

NSString * const ARCH2ThresholdECDSAWalletErrorDomain =
    @"macwlt.ARCH2ThresholdECDSAWallet";

static NSString * const kWalletFileName = @"arch2-threshold-ecdsa-wallet.plist";
static NSString * const kVersionKey = @"version";
static NSString * const kEnvelopeAKey = @"envelopeA";
static NSString * const kEnvelopeBKey = @"envelopeB";
static NSString * const kParticipantALengthKey = @"participantALength";
static NSString * const kParticipantBLengthKey = @"participantBLength";
static NSString * const kGroupPublicKeyKey = @"groupPublicKey";
static const NSInteger kCurrentVersion = 1;
static const NSUInteger kGroupPublicKeyLength = 33;
static const NSUInteger kMaximumParticipantLength = 4 * 1024 * 1024;

static NSError *walletError(ARCH2ThresholdECDSAWalletErrorCode code,
                            NSString *message) {
    return [NSError errorWithDomain:ARCH2ThresholdECDSAWalletErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setWalletError(NSError **outError,
                           ARCH2ThresholdECDSAWalletErrorCode code,
                           NSString *message) {
    if (outError) *outError = walletError(code, message);
}

static NSURL *supportDirectoryURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
                      @"Library/Application Support/macwlt"];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

static SEKeyPurpose keyPurposeForParticipant(ARCH2ThresholdECDSAParticipant participant) {
    switch (participant) {
        case ARCH2ThresholdECDSAParticipantA:
            return SEKeyPurposeARCH2ThresholdECDSAShareA;
        case ARCH2ThresholdECDSAParticipantB:
            return SEKeyPurposeARCH2ThresholdECDSAShareB;
    }
    NSCAssert(NO, @"Unhandled ARCH-2 threshold ECDSA participant");
    return SEKeyPurposeARCH2ThresholdECDSAShareA;
}

static SecKeyRef copyPublicKeyForPurpose(SEKeyPurpose purpose,
                                         NSError **outError) CF_RETURNS_RETAINED {
    SecKeyRef privateKey = [SEKeyManager copyKeyForPurpose:purpose error:outError];
    if (!privateKey) return NULL;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    CFRelease(privateKey);
    if (!publicKey) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorKeyUnavailable,
                       @"Could not load a threshold ECDSA wrapper public key");
    }
    return publicKey;
}

static NSData *wrapParticipant(NSMutableData *participant,
                               SecKeyRef publicKey,
                               NSError **outError) {
    return [WalletEnvelopeManager envelopeWrapData:participant
                                         publicKey:publicKey
                                             error:outError];
}

static NSMutableData *unwrapEnvelope(NSData *envelope,
                                     SEKeyPurpose purpose,
                                     NSError **outError) {
    SecKeyRef privateKey = [SEKeyManager copyKeyForPurpose:purpose error:outError];
    if (!privateKey) return nil;
    NSMutableData *plain = [WalletEnvelopeManager envelopeUnwrapData:envelope
                                                          privateKey:privateKey
                                                               error:outError];
    CFRelease(privateKey);
    return plain;
}

static NSData *validatedData(NSDictionary<NSString *, id> *record,
                             NSString *key,
                             NSUInteger length,
                             NSError **outError) {
    id value = record[key];
    if (![value isKindOfClass:NSData.class]) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid threshold ECDSA wallet field %@", key]);
        return nil;
    }
    NSData *data = value;
    BOOL invalidLength = length == 0 ? data.length == 0 : data.length != length;
    if (invalidLength) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid threshold ECDSA wallet field %@", key]);
        return nil;
    }
    return data;
}

static NSUInteger validatedParticipantLength(NSDictionary<NSString *, id> *record,
                                             NSString *key,
                                             NSError **outError) {
    id value = record[key];
    if (![value isKindOfClass:NSNumber.class]) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid threshold ECDSA wallet field %@", key]);
        return 0;
    }
    unsigned long long length = [value unsignedLongLongValue];
    if (length == 0 || length > kMaximumParticipantLength) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid threshold ECDSA wallet field %@", key]);
        return 0;
    }
    return (NSUInteger)length;
}

@implementation ARCH2ThresholdECDSAWallet

+ (NSURL *)defaultStorageURL {
    return [supportDirectoryURL() URLByAppendingPathComponent:kWalletFileName];
}

+ (nullable instancetype)loadOrCreateWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                                           error:(NSError **)outError {
    NSError *loadError = nil;
    ARCH2ThresholdECDSAWallet *wallet =
        [self loadFromURL:self.defaultStorageURL error:&loadError];
    if (wallet) return wallet;
    if (![loadError.domain isEqualToString:ARCH2ThresholdECDSAWalletErrorDomain] ||
        loadError.code != ARCH2ThresholdECDSAWalletErrorNotFound) {
        if (outError) *outError = loadError;
        return nil;
    }

    wallet = [self createWithLibrary:library error:outError];
    if (!wallet) return nil;
    return [wallet writeToURL:self.defaultStorageURL error:outError] ? wallet : nil;
}

+ (nullable instancetype)createWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                                      error:(NSError **)outError {
    NSParameterAssert(library);

    SecKeyRef publicKeyA =
        copyPublicKeyForPurpose(SEKeyPurposeARCH2ThresholdECDSAShareA, outError);
    if (!publicKeyA) return nil;
    SecKeyRef publicKeyB =
        copyPublicKeyForPurpose(SEKeyPurposeARCH2ThresholdECDSAShareB, outError);
    if (!publicKeyB) {
        CFRelease(publicKeyA);
        return nil;
    }

    ARCH2ThresholdECDSAKeyMaterial *material =
        [library generateKeyMaterialWithError:outError];
    if (!material) {
        CFRelease(publicKeyA);
        CFRelease(publicKeyB);
        return nil;
    }

    NSUInteger participantALength = material.participantA.length;
    NSUInteger participantBLength = material.participantB.length;
    NSData *envelopeA = nil;
    NSData *envelopeB = nil;
    @try {
        envelopeA = wrapParticipant(material.participantA, publicKeyA, outError);
        if (envelopeA) {
            envelopeB = wrapParticipant(material.participantB, publicKeyB, outError);
        }
    } @finally {
        secureWipe(material.participantA.mutableBytes, material.participantA.length);
        secureWipe(material.participantB.mutableBytes, material.participantB.length);
        CFRelease(publicKeyA);
        CFRelease(publicKeyB);
    }
    if (!envelopeA || !envelopeB) return nil;

    return [[self alloc] initWithEnvelopeA:envelopeA
                                 envelopeB:envelopeB
                        participantALength:participantALength
                        participantBLength:participantBLength
                            groupPublicKey:material.groupPublicKey];
}

+ (nullable instancetype)loadFromURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url.isFileURL);
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorNotFound,
                       @"Threshold ECDSA wallet was not found");
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
    if (!data) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:outError];
    if (![value isKindOfClass:NSDictionary.class]) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       @"Threshold ECDSA wallet record must be a dictionary");
        return nil;
    }
    NSDictionary<NSString *, id> *record = value;
    if (![record[kVersionKey] isKindOfClass:NSNumber.class] ||
        [record[kVersionKey] integerValue] != kCurrentVersion) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidRecord,
                       @"Unsupported threshold ECDSA wallet version");
        return nil;
    }

    NSData *envelopeA = validatedData(record, kEnvelopeAKey, 0, outError);
    NSData *envelopeB = validatedData(record, kEnvelopeBKey, 0, outError);
    NSData *groupPublicKey =
        validatedData(record, kGroupPublicKeyKey, kGroupPublicKeyLength, outError);
    NSUInteger participantALength =
        validatedParticipantLength(record, kParticipantALengthKey, outError);
    NSUInteger participantBLength =
        validatedParticipantLength(record, kParticipantBLengthKey, outError);
    if (!envelopeA || !envelopeB || !groupPublicKey ||
        participantALength == 0 || participantBLength == 0) {
        return nil;
    }
    return [[self alloc] initWithEnvelopeA:envelopeA
                                 envelopeB:envelopeB
                        participantALength:participantALength
                        participantBLength:participantBLength
                            groupPublicKey:groupPublicKey];
}

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                        envelopeB:(NSData *)envelopeB
               participantALength:(NSUInteger)participantALength
               participantBLength:(NSUInteger)participantBLength
                   groupPublicKey:(NSData *)groupPublicKey {
    NSParameterAssert(envelopeA.length > 0);
    NSParameterAssert(envelopeB.length > 0);
    NSParameterAssert(participantALength > 0);
    NSParameterAssert(participantBLength > 0);
    NSParameterAssert(groupPublicKey.length == kGroupPublicKeyLength);
    self = [super init];
    if (self) {
        _envelopeA = [envelopeA copy];
        _envelopeB = [envelopeB copy];
        _participantALength = participantALength;
        _participantBLength = participantBLength;
        _groupPublicKey = [groupPublicKey copy];
    }
    return self;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url.isFileURL);
    NSDictionary<NSString *, id> *record = @{
        kVersionKey: @(kCurrentVersion),
        kEnvelopeAKey: self.envelopeA,
        kEnvelopeBKey: self.envelopeB,
        kParticipantALengthKey: @(self.participantALength),
        kParticipantBLengthKey: @(self.participantBLength),
        kGroupPublicKeyKey: self.groupPublicKey,
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:outError];
    if (!data) return NO;
    NSURL *directory = [url URLByDeletingLastPathComponent];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                                withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions: @0700}
                                                      error:outError]) {
        return NO;
    }
    if (![data writeToURL:url options:NSDataWritingAtomic error:outError]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                           ofItemAtPath:url.path
                                                  error:outError];
}

- (BOOL)unwrapParticipant:(ARCH2ThresholdECDSAParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError **)outError {
    NSParameterAssert(buffer);
    NSUInteger expectedLength = participant == ARCH2ThresholdECDSAParticipantA
        ? self.participantALength : self.participantBLength;
    if (buffer.length != expectedLength ||
        buffer.state != HardenedBufferStateMasked) {
        setWalletError(outError,
                       ARCH2ThresholdECDSAWalletErrorInvalidParticipant,
                       @"Threshold ECDSA participant state requires an exact masked hardened buffer");
        return NO;
    }

    NSData *envelope = participant == ARCH2ThresholdECDSAParticipantA
        ? self.envelopeA : self.envelopeB;
    NSMutableData *plain =
        unwrapEnvelope(envelope, keyPurposeForParticipant(participant), outError);
    if (!plain) return NO;
    if (plain.length != expectedLength || ![buffer unmaskWithError:outError]) {
        secureWipe(plain.mutableBytes, plain.length);
        if (plain.length != expectedLength) {
            setWalletError(outError,
                           ARCH2ThresholdECDSAWalletErrorInvalidParticipant,
                           @"Unwrapped threshold ECDSA participant state has an invalid length");
        }
        return NO;
    }
    memcpy(buffer.mutableBytes, plain.bytes, expectedLength);
    secureWipe(plain.mutableBytes, plain.length);
    return YES;
}

@end
