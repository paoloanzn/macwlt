/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2FROSTWallet.h"

#import "ARCH2FROSTLibrary.h"
#import "HardenedBuffer.h"
#import "SEKeyManager.h"
#import "SecureWipe.h"
#import "WalletEnvelopeManager.h"
#import "WalletPublicKeyDerivation.h"

#include <wally_crypto.h>

NSString * const ARCH2FROSTWalletErrorDomain = @"macwlt.ARCH2FROSTWallet";

static NSString * const kARCH2WalletFileName = @"arch2-frost-wallet.plist";
static NSString * const kVersionKey = @"version";
static NSString * const kEnvelopeAKey = @"envelopeA";
static NSString * const kEnvelopeBKey = @"envelopeB";
static NSString * const kParticipantPublicKeyAKey = @"participantPublicKeyA";
static NSString * const kParticipantPublicKeyBKey = @"participantPublicKeyB";
static NSString * const kGroupPublicKeyKey = @"groupPublicKey";
static NSString * const kChainCodeKey = @"chainCode";
static const NSInteger kCurrentVersion = 1;
static const uint32_t kParticipantCount = 2;
static const uint32_t kThreshold = 2;

static NSError *walletError(ARCH2FROSTWalletErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ARCH2FROSTWalletErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setWalletError(NSError **outError,
                           ARCH2FROSTWalletErrorCode code,
                           NSString *message) {
    if (outError) *outError = walletError(code, message);
}

static NSURL *supportDirectoryURL(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
                      @"Library/Application Support/macwlt"];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

static SEKeyPurpose keyPurposeForParticipant(ARCH2FROSTParticipant participant) {
    switch (participant) {
        case ARCH2FROSTParticipantA:
            return SEKeyPurposeARCH2ShareA;
        case ARCH2FROSTParticipantB:
            return SEKeyPurposeARCH2ShareB;
    }
    NSCAssert(NO, @"Unhandled ARCH-2 participant");
    return SEKeyPurposeARCH2ShareA;
}

static SecKeyRef copyPublicKeyForPurpose(SEKeyPurpose purpose,
                                         NSError **outError) CF_RETURNS_RETAINED {
    SecKeyRef privateKey = [SEKeyManager copyKeyForPurpose:purpose error:outError];
    if (!privateKey) return NULL;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    CFRelease(privateKey);
    if (!publicKey) {
        setWalletError(outError, ARCH2FROSTWalletErrorKeyUnavailable,
                       @"Could not load an ARCH-2 wrapper public key");
    }
    return publicKey;
}

static NSData *wrapScalarBytes(const unsigned char *bytes,
                               SecKeyRef publicKey,
                               NSError **outError) {
    NSMutableData *plain = [NSMutableData dataWithBytes:bytes length:32];
    NSData *envelope = nil;
    @try {
        envelope = [WalletEnvelopeManager envelopeWrap:plain
                                             publicKey:publicKey
                                                 error:outError];
    } @finally {
        secureWipe(plain.mutableBytes, plain.length);
    }
    return envelope;
}

static NSMutableData *unwrapEnvelope(NSData *envelope,
                                     SEKeyPurpose purpose,
                                     NSError **outError) {
    SecKeyRef privateKey = [SEKeyManager copyKeyForPurpose:purpose error:outError];
    if (!privateKey) return nil;
    NSMutableData *plain = [WalletEnvelopeManager envelopeUnwrap:envelope
                                                      privateKey:privateKey
                                                          error:outError];
    CFRelease(privateKey);
    return plain;
}

static BOOL negateSecret(unsigned char secret[32]) {
    unsigned char zero[32] = {0};
    unsigned char negated[32] = {0};
    int result = wally_ec_scalar_subtract(zero, sizeof(zero),
                                          secret, 32,
                                          negated, sizeof(negated));
    if (result == WALLY_OK) memcpy(secret, negated, sizeof(negated));
    secureWipe(negated, sizeof(negated));
    return result == WALLY_OK;
}

static BOOL normalizeKeypair(secp256k1_frost_keypair *keypair,
                             ARCH2FROSTLibrary *library,
                             unsigned char participantPublicKey33[33],
                             unsigned char groupPublicKey33[33]) {
    if (![library savePublicKey:&keypair->public_keys
        participantPublicKey33:participantPublicKey33
             groupPublicKey33:groupPublicKey33]) {
        return NO;
    }
    if (groupPublicKey33[0] != 0x03) return groupPublicKey33[0] == 0x02;

    unsigned char normalizedParticipant[33] = {0};
    unsigned char normalizedGroup[33] = {0};
    if (!negateSecret(keypair->secret) ||
        wally_ec_public_key_negate(participantPublicKey33, 33,
                                   normalizedParticipant, 33) != WALLY_OK ||
        wally_ec_public_key_negate(groupPublicKey33, 33,
                                   normalizedGroup, 33) != WALLY_OK) {
        secureWipe(normalizedParticipant, sizeof(normalizedParticipant));
        secureWipe(normalizedGroup, sizeof(normalizedGroup));
        return NO;
    }
    memcpy(participantPublicKey33, normalizedParticipant, 33);
    memcpy(groupPublicKey33, normalizedGroup, 33);
    secureWipe(normalizedParticipant, sizeof(normalizedParticipant));
    secureWipe(normalizedGroup, sizeof(normalizedGroup));
    return [library loadPublicKey:&keypair->public_keys
                           index:keypair->public_keys.index
                participantCount:kParticipantCount
         participantPublicKey33:participantPublicKey33
              groupPublicKey33:groupPublicKey33];
}

static NSData *validatedData(NSDictionary<NSString *, id> *record,
                             NSString *key,
                             NSUInteger length,
                             NSError **outError) {
    id value = record[key];
    if (![value isKindOfClass:NSData.class]) {
        setWalletError(outError, ARCH2FROSTWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid ARCH-2 wallet field %@", key]);
        return nil;
    }
    NSData *data = value;
    BOOL invalidLength = length == 0
        ? data.length == 0
        : data.length != length;
    if (invalidLength) {
        setWalletError(outError, ARCH2FROSTWalletErrorInvalidRecord,
                       [NSString stringWithFormat:@"Invalid ARCH-2 wallet field %@", key]);
        return nil;
    }
    return data;
}

@implementation ARCH2FROSTWallet

+ (NSURL *)defaultStorageURL {
    return [supportDirectoryURL() URLByAppendingPathComponent:kARCH2WalletFileName];
}

+ (nullable instancetype)loadOrCreateWithLibrary:(ARCH2FROSTLibrary *)library
                                           error:(NSError **)outError {
    NSError *loadError = nil;
    ARCH2FROSTWallet *wallet = [self loadFromURL:self.defaultStorageURL error:&loadError];
    if (wallet) return wallet;
    if (![loadError.domain isEqualToString:ARCH2FROSTWalletErrorDomain] ||
        loadError.code != ARCH2FROSTWalletErrorNotFound) {
        if (outError) *outError = loadError;
        return nil;
    }

    wallet = [self createWithLibrary:library error:outError];
    if (!wallet) return nil;
    return [wallet writeToURL:self.defaultStorageURL error:outError] ? wallet : nil;
}

+ (nullable instancetype)createWithLibrary:(ARCH2FROSTLibrary *)library
                                      error:(NSError **)outError {
    NSParameterAssert(library);

    SecKeyRef publicKeyA = copyPublicKeyForPurpose(SEKeyPurposeARCH2ShareA, outError);
    if (!publicKeyA) return nil;
    SecKeyRef publicKeyB = copyPublicKeyForPurpose(SEKeyPurposeARCH2ShareB, outError);
    if (!publicKeyB) {
        CFRelease(publicKeyA);
        return nil;
    }

    NSData *context = [@"macwlt-arch2-frost-dkg-v1" dataUsingEncoding:NSUTF8StringEncoding];
    secp256k1_frost_vss_commitments *commitments[2] = {
        [library createVSSCommitmentsWithThreshold:kThreshold],
        [library createVSSCommitmentsWithThreshold:kThreshold],
    };
    if (!commitments[0] || !commitments[1]) {
        [library destroyVSSCommitments:commitments[0]];
        [library destroyVSSCommitments:commitments[1]];
        CFRelease(publicKeyA);
        CFRelease(publicKeyB);
        setWalletError(outError, ARCH2FROSTWalletErrorDKGFailed,
                       @"Could not allocate FROST DKG commitments");
        return nil;
    }

    NSData *inbox[2][2] = {{nil, nil}, {nil, nil}};
    secp256k1_frost_keygen_secret_share generated[2];
    memset(generated, 0, sizeof(generated));
    BOOL dkgOK = YES;
    for (uint32_t generator = 1; generator <= kParticipantCount && dkgOK; generator++) {
        dkgOK = [library beginDKGWithCommitments:commitments[generator - 1]
                                         shares:generated
                                   participants:kParticipantCount
                                      threshold:kThreshold
                                 generatorIndex:generator
                                        context:context];
        if (dkgOK) {
            inbox[generator - 1][0] = wrapScalarBytes(generated[0].value,
                                                      publicKeyA, outError);
            secureWipe(&generated[0], sizeof(generated[0]));
            dkgOK = inbox[generator - 1][0] != nil;
        }
        if (dkgOK) {
            inbox[generator - 1][1] = wrapScalarBytes(generated[1].value,
                                                      publicKeyB, outError);
            secureWipe(&generated[1], sizeof(generated[1]));
            dkgOK = inbox[generator - 1][1] != nil;
        }
        secureWipe(generated, sizeof(generated));
    }
    CFRelease(publicKeyA);
    CFRelease(publicKeyB);

    if (dkgOK) {
        dkgOK = [library validateCommitment:commitments[0] context:context] &&
            [library validateCommitment:commitments[1] context:context];
    }

    NSData *finalEnvelopes[2] = {nil, nil};
    NSData *participantPublicKeys[2] = {nil, nil};
    NSData *groupPublicKey = nil;
    unsigned char expectedGroup[33] = {0};

    for (uint32_t receiver = 1; receiver <= kParticipantCount && dkgOK; receiver++) {
        SEKeyPurpose purpose = receiver == 1
            ? SEKeyPurposeARCH2ShareA : SEKeyPurposeARCH2ShareB;
        secp256k1_frost_keygen_secret_share received[2];
        secp256k1_frost_keypair keypair;
        memset(received, 0, sizeof(received));
        memset(&keypair, 0, sizeof(keypair));

        for (uint32_t generator = 1; generator <= kParticipantCount && dkgOK; generator++) {
            NSMutableData *plain = unwrapEnvelope(inbox[generator - 1][receiver - 1],
                                                  purpose, outError);
            if (!plain) {
                dkgOK = NO;
                break;
            }
            received[generator - 1].generator_index = generator;
            received[generator - 1].receiver_index = receiver;
            memcpy(received[generator - 1].value, plain.bytes, 32);
            secureWipe(plain.mutableBytes, plain.length);
        }

        if (dkgOK) {
            dkgOK = [library finalizeDKGForParticipant:receiver
                                               shares:received
                                          commitments:commitments
                                              keypair:&keypair];
        }

        unsigned char participantPublic[33] = {0};
        unsigned char normalizedGroup[33] = {0};
        if (dkgOK) {
            dkgOK = normalizeKeypair(&keypair, library,
                                     participantPublic, normalizedGroup);
        }
        if (dkgOK && receiver == 1) {
            memcpy(expectedGroup, normalizedGroup, sizeof(expectedGroup));
            groupPublicKey = [NSData dataWithBytes:normalizedGroup length:33];
        } else if (dkgOK) {
            dkgOK = memcmp(expectedGroup, normalizedGroup, 33) == 0;
        }

        if (dkgOK) {
            SecKeyRef wrapperPublicKey = copyPublicKeyForPurpose(purpose, outError);
            if (!wrapperPublicKey) {
                dkgOK = NO;
            } else {
                finalEnvelopes[receiver - 1] = wrapScalarBytes(keypair.secret,
                                                               wrapperPublicKey,
                                                               outError);
                CFRelease(wrapperPublicKey);
                dkgOK = finalEnvelopes[receiver - 1] != nil;
            }
        }
        if (dkgOK) {
            participantPublicKeys[receiver - 1] =
                [NSData dataWithBytes:participantPublic length:33];
        }

        secureWipe(received, sizeof(received));
        secureWipe(&keypair, sizeof(keypair));
        secureWipe(participantPublic, sizeof(participantPublic));
        secureWipe(normalizedGroup, sizeof(normalizedGroup));
    }

    [library destroyVSSCommitments:commitments[0]];
    [library destroyVSSCommitments:commitments[1]];
    secureWipe(expectedGroup, sizeof(expectedGroup));

    if (!dkgOK) {
        if (outError && !*outError) {
            setWalletError(outError, ARCH2FROSTWalletErrorDKGFailed,
                           @"FROST distributed key generation failed");
        }
        return nil;
    }

    NSData *chainCode = [WalletPublicKeyDerivation randomChainCodeWithError:outError];
    if (!chainCode) return nil;
    return [[self alloc] initWithEnvelopeA:finalEnvelopes[0]
                                 envelopeB:finalEnvelopes[1]
                      participantPublicKeyA:participantPublicKeys[0]
                      participantPublicKeyB:participantPublicKeys[1]
                            groupPublicKey:groupPublicKey
                                 chainCode:chainCode];
}

+ (nullable instancetype)loadFromURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url.isFileURL);
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        setWalletError(outError, ARCH2FROSTWalletErrorNotFound,
                       @"ARCH-2 wallet was not found");
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
    if (!data) return nil;
    id value = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:outError];
    if (![value isKindOfClass:NSDictionary.class]) {
        setWalletError(outError, ARCH2FROSTWalletErrorInvalidRecord,
                       @"ARCH-2 wallet record must be a dictionary");
        return nil;
    }
    NSDictionary<NSString *, id> *record = value;
    if (![record[kVersionKey] isKindOfClass:NSNumber.class] ||
        [record[kVersionKey] integerValue] != kCurrentVersion) {
        setWalletError(outError, ARCH2FROSTWalletErrorInvalidRecord,
                       @"Unsupported ARCH-2 wallet version");
        return nil;
    }

    NSData *envelopeA = validatedData(record, kEnvelopeAKey, 0, outError);
    NSData *envelopeB = validatedData(record, kEnvelopeBKey, 0, outError);
    NSData *participantA = validatedData(record, kParticipantPublicKeyAKey, 33, outError);
    NSData *participantB = validatedData(record, kParticipantPublicKeyBKey, 33, outError);
    NSData *group = validatedData(record, kGroupPublicKeyKey, 33, outError);
    NSData *chainCode = validatedData(record, kChainCodeKey, 32, outError);
    if (!envelopeA || !envelopeB || !participantA || !participantB ||
        !group || !chainCode) {
        return nil;
    }
    return [[self alloc] initWithEnvelopeA:envelopeA
                                 envelopeB:envelopeB
                      participantPublicKeyA:participantA
                      participantPublicKeyB:participantB
                            groupPublicKey:group
                                 chainCode:chainCode];
}

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                        envelopeB:(NSData *)envelopeB
             participantPublicKeyA:(NSData *)participantPublicKeyA
             participantPublicKeyB:(NSData *)participantPublicKeyB
                    groupPublicKey:(NSData *)groupPublicKey
                         chainCode:(NSData *)chainCode {
    NSParameterAssert(envelopeA.length > 0);
    NSParameterAssert(envelopeB.length > 0);
    NSParameterAssert(participantPublicKeyA.length == 33);
    NSParameterAssert(participantPublicKeyB.length == 33);
    NSParameterAssert(groupPublicKey.length == 33);
    NSParameterAssert(chainCode.length == 32);

    self = [super init];
    if (self) {
        _envelopeA = [envelopeA copy];
        _envelopeB = [envelopeB copy];
        _participantPublicKeyA = [participantPublicKeyA copy];
        _participantPublicKeyB = [participantPublicKeyB copy];
        _groupPublicKey = [groupPublicKey copy];
        _chainCode = [chainCode copy];
    }
    return self;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url.isFileURL);
    NSDictionary<NSString *, id> *record = @{
        kVersionKey: @(kCurrentVersion),
        kEnvelopeAKey: self.envelopeA,
        kEnvelopeBKey: self.envelopeB,
        kParticipantPublicKeyAKey: self.participantPublicKeyA,
        kParticipantPublicKeyBKey: self.participantPublicKeyB,
        kGroupPublicKeyKey: self.groupPublicKey,
        kChainCodeKey: self.chainCode,
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

- (BOOL)unwrapParticipant:(ARCH2FROSTParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError **)outError {
    NSParameterAssert(buffer);
    if (buffer.length < 32 || buffer.state != HardenedBufferStateMasked) {
        setWalletError(outError, ARCH2FROSTWalletErrorInvalidShare,
                       @"ARCH-2 shares require a masked 32-byte hardened buffer");
        return NO;
    }

    NSData *envelope = participant == ARCH2FROSTParticipantA
        ? self.envelopeA : self.envelopeB;
    NSMutableData *plain = unwrapEnvelope(envelope,
                                          keyPurposeForParticipant(participant),
                                          outError);
    if (!plain) return NO;
    if (plain.length != 32 || ![buffer unmaskWithError:outError]) {
        secureWipe(plain.mutableBytes, plain.length);
        if (plain.length != 32) {
            setWalletError(outError, ARCH2FROSTWalletErrorInvalidShare,
                           @"Unwrapped ARCH-2 share must be 32 bytes");
        }
        return NO;
    }
    memcpy(buffer.mutableBytes, plain.bytes, 32);
    secureWipe(plain.mutableBytes, plain.length);
    return YES;
}

@end
