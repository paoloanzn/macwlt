/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2ThresholdECDSASigningEngine.h"

#import "ARCH2ThresholdECDSALibrary.h"
#import "ARCH2ThresholdECDSAWallet.h"
#import "HardenedBuffer.h"
#import "SecureWipe.h"

#import <dispatch/dispatch.h>
#import <secp256k1.h>
#import <secp256k1_recovery.h>

#include <KeccakHash.h>
#include <string.h>
#include <wally_core.h>

NSString * const ARCH2ThresholdECDSASigningEngineErrorDomain =
    @"macwlt.ARCH2ThresholdECDSASigningEngine";

static const NSUInteger kDigestLength = 32;
static const NSUInteger kCompactSignatureLength = 64;
static const NSUInteger kEthereumSignatureLength = 65;
static const NSUInteger kCompressedPublicKeyLength = 33;
static const NSUInteger kMaximumRecoveryAttempts = 4;

static NSError *engineError(ARCH2ThresholdECDSASigningEngineErrorCode code,
                            NSString *message) {
    return [NSError errorWithDomain:ARCH2ThresholdECDSASigningEngineErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setEngineError(NSError **outError,
                           ARCH2ThresholdECDSASigningEngineErrorCode code,
                           NSString *message) {
    if (outError) *outError = engineError(code, message);
}

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
}

static secp256k1_context *signerContext(NSError **outError) {
    secp256k1_context *context =
        ensureWallyInitialized() ? wally_get_secp_context() : NULL;
    if (!context) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorWalletUnavailable,
                       @"Could not create a secp256k1 recovery context");
    }
    return context;
}

static BOOL keccak256(NSData *message, unsigned char digest[kDigestLength]) {
    Keccak_HashInstance hash;
    if (Keccak_HashInitialize(&hash, 1088, 512, 256, 0x01) != KECCAK_SUCCESS) {
        return NO;
    }
    if (Keccak_HashUpdate(&hash, message.bytes, message.length * 8) != KECCAK_SUCCESS) {
        return NO;
    }
    return Keccak_HashFinal(&hash, digest) == KECCAK_SUCCESS;
}

static NSInteger recoveryIDForSignature(NSData *signature,
                                        NSData *transaction,
                                        NSData *groupPublicKey,
                                        NSError **outError) {
    if (signature.length != kCompactSignatureLength ||
        groupPublicKey.length != kCompressedPublicKeyLength) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorRecoveryFailed,
                       @"Threshold ECDSA produced invalid recovery material");
        return -1;
    }

    secp256k1_context *context = signerContext(outError);
    if (!context) return -1;
    unsigned char digest[kDigestLength];
    if (!keccak256(transaction, digest)) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorRecoveryFailed,
                       @"Could not hash the Ethereum signing preimage");
        return -1;
    }

    NSInteger matchingRecoveryID = -1;
    for (int recoveryID = 0; recoveryID < 4; recoveryID++) {
        secp256k1_ecdsa_recoverable_signature recoverable;
        secp256k1_pubkey recovered;
        unsigned char compressed[kCompressedPublicKeyLength];
        size_t compressedLength = sizeof(compressed);
        if (secp256k1_ecdsa_recoverable_signature_parse_compact(
                context, &recoverable, signature.bytes, recoveryID) &&
            secp256k1_ecdsa_recover(context, &recovered, &recoverable, digest) &&
            secp256k1_ec_pubkey_serialize(context,
                                          compressed,
                                          &compressedLength,
                                          &recovered,
                                          SECP256K1_EC_COMPRESSED) &&
            compressedLength == kCompressedPublicKeyLength &&
            memcmp(compressed,
                   groupPublicKey.bytes,
                   kCompressedPublicKeyLength) == 0) {
            matchingRecoveryID = recoveryID;
            secureWipe(compressed, sizeof(compressed));
            break;
        }
        secureWipe(compressed, sizeof(compressed));
    }
    secureWipe(digest, sizeof(digest));
    if (matchingRecoveryID < 0) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorRecoveryFailed,
                       @"Could not recover the threshold ECDSA public key");
    }
    return matchingRecoveryID;
}

@implementation ARCH2ThresholdECDSASigningEngine {
    NSLock *_sessionLock;
}

+ (nullable instancetype)engineWithError:(NSError **)outError {
    ARCH2ThresholdECDSALibrary *library = [ARCH2ThresholdECDSALibrary library];
    ARCH2ThresholdECDSAWallet *wallet =
        [ARCH2ThresholdECDSAWallet loadOrCreateWithLibrary:library error:outError];
    if (!wallet) return nil;
    return [[self alloc] initWithLibrary:library wallet:wallet];
}

- (instancetype)initWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                         wallet:(ARCH2ThresholdECDSAWallet *)wallet {
    NSParameterAssert(library);
    NSParameterAssert(wallet);
    self = [super init];
    if (self) {
        _library = library;
        _wallet = wallet;
        _sessionLock = [[NSLock alloc] init];
    }
    return self;
}

- (NSData *)groupPublicKey {
    return [self.wallet.groupPublicKey copy];
}

- (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                               error:(NSError **)outError {
    if (transaction.length == 0) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorInvalidTransaction,
                       @"Ethereum transaction signing preimage must not be empty");
        return nil;
    }

    NSError *memoryError = nil;
    HardenedBuffer *participantA =
        [HardenedBuffer bufferWithLength:self.wallet.participantALength
                                   error:&memoryError];
    HardenedBuffer *participantB =
        [HardenedBuffer bufferWithLength:self.wallet.participantBLength
                                   error:&memoryError];
    if (!participantA || !participantB) {
        setEngineError(outError,
                       ARCH2ThresholdECDSASigningEngineErrorMemoryProtectionFailed,
                       memoryError.localizedDescription ?: @"Could not protect threshold participant memory");
        return nil;
    }

    [_sessionLock lock];
    NSData *ethereumSignature = nil;
    NSError *operationError = nil;
    @try {
        BOOL unwrapped =
            [self.wallet unwrapParticipant:ARCH2ThresholdECDSAParticipantA
                       intoHardenedBuffer:participantA
                                    error:&operationError] &&
            [self.wallet unwrapParticipant:ARCH2ThresholdECDSAParticipantB
                       intoHardenedBuffer:participantB
                                    error:&operationError];
        if (unwrapped) {
            NSData *stateA =
                [NSData dataWithBytesNoCopy:participantA.mutableBytes
                                     length:participantA.length
                               freeWhenDone:NO];
            NSData *stateB =
                [NSData dataWithBytesNoCopy:participantB.mutableBytes
                                     length:participantB.length
                               freeWhenDone:NO];
            for (NSUInteger attempt = 0;
                 attempt < kMaximumRecoveryAttempts && !ethereumSignature;
                 attempt++) {
                NSData *compact =
                    [self.library signTransaction:transaction
                                     participantA:stateA
                                     participantB:stateB
                                            error:&operationError];
                if (!compact) break;
                NSInteger recoveryID =
                    recoveryIDForSignature(compact,
                                           transaction,
                                           self.wallet.groupPublicKey,
                                           &operationError);
                if (recoveryID < 0) break;
                if (recoveryID >= 2) continue;

                NSMutableData *output = [compact mutableCopy];
                uint8_t parity = (uint8_t)recoveryID;
                [output appendBytes:&parity length:sizeof(parity)];
                if (output.length == kEthereumSignatureLength) {
                    ethereumSignature = output;
                }
            }
            if (!ethereumSignature && !operationError) {
                operationError =
                    engineError(ARCH2ThresholdECDSASigningEngineErrorSigningFailed,
                                @"Could not produce an Ethereum-compatible recovery parity");
            }
        }
    } @finally {
        NSError *cleanupError = nil;
        BOOL cleanedA = [participantA wipeAndMaskWithError:&cleanupError];
        BOOL cleanedB = [participantB wipeAndMaskWithError:&cleanupError];
        [_sessionLock unlock];
        if ((!cleanedA || !cleanedB) && ethereumSignature) {
            ethereumSignature = nil;
            operationError =
                engineError(ARCH2ThresholdECDSASigningEngineErrorMemoryProtectionFailed,
                            cleanupError.localizedDescription ?:
                                @"Could not clear threshold participant memory");
        }
    }

    if (!ethereumSignature && outError) {
        *outError = operationError ?:
            engineError(ARCH2ThresholdECDSASigningEngineErrorSigningFailed,
                        @"Threshold ECDSA signing failed");
    }
    return ethereumSignature;
}

@end
