/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2FROSTSigningEngine.h"

#import "ARCH2FROSTLibrary.h"
#import "ARCH2FROSTWallet.h"
#import "HardenedBuffer.h"
#import "SecureWipe.h"
#import "WalletPublicKeyDerivation.h"

#import <Security/Security.h>

#include <wally_bip32.h>
#include <wally_core.h>
#include <wally_crypto.h>
#include <wally_map.h>
#include <wally_psbt.h>
#include <wally_psbt_members.h>
#include <wally_transaction.h>

NSString * const ARCH2FROSTSigningEngineErrorDomain =
    @"macwlt.ARCH2FROSTSigningEngine";

static const NSUInteger kDigestLength = 32;
static const NSUInteger kSignatureLength = 64;
static const NSUInteger kNonceSeedLength = 64;
static const uint32_t kPSBTInputTapMerkleRoot = 0x18;

@interface ARCH2FROSTSigningMaterial : NSObject

@property (nonatomic, copy, readonly) NSData *participantPublicKeyA;
@property (nonatomic, copy, readonly) NSData *participantPublicKeyB;
@property (nonatomic, copy, readonly) NSData *groupPublicKey;
@property (nonatomic, copy, readonly) NSData *derivationTweak;
@property (nonatomic, readonly) BOOL negateAfterDerivation;
@property (nonatomic, copy, readonly) NSData *taprootTweak;
@property (nonatomic, readonly) BOOL negateAfterTaproot;

- (instancetype)initWithParticipantPublicKeyA:(NSData *)participantPublicKeyA
                        participantPublicKeyB:(NSData *)participantPublicKeyB
                               groupPublicKey:(NSData *)groupPublicKey
                            derivationTweak:(NSData *)derivationTweak
                      negateAfterDerivation:(BOOL)negateAfterDerivation
                               taprootTweak:(NSData *)taprootTweak
                         negateAfterTaproot:(BOOL)negateAfterTaproot;

@end

@implementation ARCH2FROSTSigningMaterial

- (instancetype)initWithParticipantPublicKeyA:(NSData *)participantPublicKeyA
                        participantPublicKeyB:(NSData *)participantPublicKeyB
                               groupPublicKey:(NSData *)groupPublicKey
                            derivationTweak:(NSData *)derivationTweak
                      negateAfterDerivation:(BOOL)negateAfterDerivation
                               taprootTweak:(NSData *)taprootTweak
                         negateAfterTaproot:(BOOL)negateAfterTaproot {
    NSParameterAssert(participantPublicKeyA.length == 33);
    NSParameterAssert(participantPublicKeyB.length == 33);
    NSParameterAssert(groupPublicKey.length == 33);
    NSParameterAssert(derivationTweak.length == 32);
    NSParameterAssert(taprootTweak.length == 0 || taprootTweak.length == 32);
    self = [super init];
    if (self) {
        _participantPublicKeyA = [participantPublicKeyA copy];
        _participantPublicKeyB = [participantPublicKeyB copy];
        _groupPublicKey = [groupPublicKey copy];
        _derivationTweak = [derivationTweak copy];
        _negateAfterDerivation = negateAfterDerivation;
        _taprootTweak = [taprootTweak copy];
        _negateAfterTaproot = negateAfterTaproot;
    }
    return self;
}

@end

static NSError *engineError(ARCH2FROSTSigningEngineErrorCode code,
                            NSString *message) {
    return [NSError errorWithDomain:ARCH2FROSTSigningEngineErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setEngineError(NSError **outError,
                           ARCH2FROSTSigningEngineErrorCode code,
                           NSString *message) {
    if (outError) *outError = engineError(code, message);
}

static BOOL scalarIsZero(const unsigned char scalar[32]) {
    unsigned char result = 0;
    for (NSUInteger index = 0; index < 32; index++) result |= scalar[index];
    return result == 0;
}

static BOOL tweakPublicKey(unsigned char publicKey[33],
                           const unsigned char tweak[32]) {
    if (scalarIsZero(tweak)) return YES;
    unsigned char output[33] = {0};
    int result = wally_ec_public_key_tweak(publicKey, 33, tweak, 32,
                                           output, sizeof(output));
    if (result == WALLY_OK) memcpy(publicKey, output, sizeof(output));
    secureWipe(output, sizeof(output));
    return result == WALLY_OK;
}

static BOOL negatePublicKey(unsigned char publicKey[33]) {
    unsigned char output[33] = {0};
    int result = wally_ec_public_key_negate(publicKey, 33,
                                            output, sizeof(output));
    if (result == WALLY_OK) memcpy(publicKey, output, sizeof(output));
    secureWipe(output, sizeof(output));
    return result == WALLY_OK;
}

static BOOL transformShare(unsigned char share[32],
                           ARCH2FROSTSigningMaterial *material) {
    unsigned char output[32] = {0};
    unsigned char zero[32] = {0};
    BOOL ok = YES;
    if (!scalarIsZero(material.derivationTweak.bytes)) {
        ok = wally_ec_scalar_add(share, 32,
                                 material.derivationTweak.bytes, 32,
                                 output, sizeof(output)) == WALLY_OK;
        if (ok) memcpy(share, output, sizeof(output));
    }
    if (ok && material.negateAfterDerivation) {
        ok = wally_ec_scalar_subtract(zero, sizeof(zero), share, 32,
                                      output, sizeof(output)) == WALLY_OK;
        if (ok) memcpy(share, output, sizeof(output));
    }
    if (ok && material.taprootTweak.length == 32 &&
        !scalarIsZero(material.taprootTweak.bytes)) {
        ok = wally_ec_scalar_add(share, 32,
                                 material.taprootTweak.bytes, 32,
                                 output, sizeof(output)) == WALLY_OK;
        if (ok) memcpy(share, output, sizeof(output));
    }
    if (ok && material.negateAfterTaproot) {
        ok = wally_ec_scalar_subtract(zero, sizeof(zero), share, 32,
                                      output, sizeof(output)) == WALLY_OK;
        if (ok) memcpy(share, output, sizeof(output));
    }
    secureWipe(output, sizeof(output));
    return ok;
}

static BOOL loadPublicMaterial(ARCH2FROSTLibrary *library,
                               ARCH2FROSTSigningMaterial *material,
                               ARCH2FROSTParticipant participant,
                               secp256k1_frost_pubkey *publicKey) {
    NSData *participantKey = participant == ARCH2FROSTParticipantA
        ? material.participantPublicKeyA : material.participantPublicKeyB;
    return [library loadPublicKey:publicKey
                           index:(uint32_t)participant
                participantCount:2
         participantPublicKey33:participantKey.bytes
              groupPublicKey33:material.groupPublicKey.bytes];
}

static BOOL loadKeypair(ARCH2FROSTLibrary *library,
                        ARCH2FROSTSigningMaterial *material,
                        ARCH2FROSTParticipant participant,
                        const unsigned char *share,
                        secp256k1_frost_keypair *keypair) {
    memset(keypair, 0, sizeof(*keypair));
    memcpy(keypair->secret, share, 32);
    return transformShare(keypair->secret, material) &&
        loadPublicMaterial(library, material, participant, &keypair->public_keys);
}

static BOOL derivePublicKeyAndTweak(NSData *rootPublicKey,
                                    NSData *rootChainCode,
                                    const uint32_t *path,
                                    size_t pathLength,
                                    unsigned char outPublicKey[33],
                                    unsigned char outTweak[32]) {
    unsigned char currentPublicKey[33];
    unsigned char currentChainCode[32];
    unsigned char tweakSum[32] = {0};
    memcpy(currentPublicKey, rootPublicKey.bytes, sizeof(currentPublicKey));
    memcpy(currentChainCode, rootChainCode.bytes, sizeof(currentChainCode));

    BOOL ok = YES;
    for (size_t index = 0; index < pathLength && ok; index++) {
        uint32_t child = path[index];
        if ((child & BIP32_INITIAL_HARDENED_CHILD) != 0) {
            ok = NO;
            break;
        }
        unsigned char data[37];
        unsigned char hmac[HMAC_SHA512_LEN];
        unsigned char nextPublicKey[33];
        memcpy(data, currentPublicKey, 33);
        data[33] = (unsigned char)(child >> 24);
        data[34] = (unsigned char)(child >> 16);
        data[35] = (unsigned char)(child >> 8);
        data[36] = (unsigned char)child;
        ok = wally_hmac_sha512(currentChainCode, sizeof(currentChainCode),
                               data, sizeof(data),
                               hmac, sizeof(hmac)) == WALLY_OK &&
            wally_ec_scalar_verify(hmac, 32) == WALLY_OK &&
            wally_ec_public_key_tweak(currentPublicKey, 33,
                                      hmac, 32,
                                      nextPublicKey, sizeof(nextPublicKey)) == WALLY_OK;
        if (ok) {
            unsigned char nextTweak[32] = {0};
            ok = wally_ec_scalar_add(tweakSum, sizeof(tweakSum),
                                     hmac, 32,
                                     nextTweak, sizeof(nextTweak)) == WALLY_OK;
            if (ok) {
                memcpy(tweakSum, nextTweak, sizeof(tweakSum));
                memcpy(currentPublicKey, nextPublicKey, sizeof(currentPublicKey));
                memcpy(currentChainCode, hmac + 32, sizeof(currentChainCode));
            }
            secureWipe(nextTweak, sizeof(nextTweak));
        }
        secureWipe(data, sizeof(data));
        secureWipe(hmac, sizeof(hmac));
        secureWipe(nextPublicKey, sizeof(nextPublicKey));
    }
    if (ok) {
        memcpy(outPublicKey, currentPublicKey, 33);
        memcpy(outTweak, tweakSum, 32);
    }
    secureWipe(currentChainCode, sizeof(currentChainCode));
    secureWipe(tweakSum, sizeof(tweakSum));
    return ok;
}

@implementation ARCH2FROSTSigningEngine {
    NSLock *_sessionLock;
}

+ (nullable instancetype)engineWithError:(NSError **)outError {
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:outError];
    if (!library) return nil;
    ARCH2FROSTWallet *wallet = [ARCH2FROSTWallet loadOrCreateWithLibrary:library
                                                                  error:outError];
    if (!wallet) return nil;
    return [[self alloc] initWithLibrary:library wallet:wallet];
}

- (instancetype)initWithLibrary:(ARCH2FROSTLibrary *)library
                         wallet:(ARCH2FROSTWallet *)wallet {
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

- (nullable NSData *)publicKeyForDerivationPath:(NSString *)derivationPath
                                          error:(NSError **)outError {
    return [WalletPublicKeyDerivation
        publicKeyForRootCompressedPublicKey:self.wallet.groupPublicKey
                                  chainCode:self.wallet.chainCode
                             derivationPath:derivationPath
                                      error:outError];
}

- (nullable NSData *)signDigest:(NSData *)digest error:(NSError **)outError {
    if (digest.length != kDigestLength) {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"FROST signing requires a 32-byte digest");
        return nil;
    }

    [_sessionLock lock];
    @try {
        ARCH2FROSTSigningMaterial *material =
            [self signingMaterialForPath:NULL
                              pathLength:0
                       taprootMerkleRoot:nil
                                   error:outError];
        if (!material) return nil;
        return [self signDigestInSerializedSession:digest
                                         material:material
                                            error:outError];
    } @finally {
        [_sessionLock unlock];
    }
}

- (nullable NSData *)signTaprootDigest:(NSData *)digest
                        derivationPath:(NSString *)derivationPath
                            merkleRoot:(nullable NSData *)merkleRoot
                                 error:(NSError **)outError {
    if (digest.length != kDigestLength ||
        (![derivationPath isEqualToString:@"m"] &&
         ![derivationPath hasPrefix:@"m/"])) {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"Taproot signing requires a 32-byte digest and m-based path");
        return nil;
    }

    NSArray<NSString *> *components =
        [derivationPath componentsSeparatedByString:@"/"];
    NSMutableData *pathData =
        [NSMutableData dataWithLength:(components.count - 1) * sizeof(uint32_t)];
    uint32_t *path = pathData.mutableBytes;
    for (NSUInteger index = 1; index < components.count; index++) {
        NSString *component = components[index];
        NSScanner *scanner = [NSScanner scannerWithString:component];
        unsigned long long value = 0;
        if (component.length == 0 ||
            ![scanner scanUnsignedLongLong:&value] ||
            !scanner.isAtEnd ||
            value >= BIP32_INITIAL_HARDENED_CHILD) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                           @"Taproot derivation path must contain non-hardened indexes");
            return nil;
        }
        path[index - 1] = (uint32_t)value;
    }

    [_sessionLock lock];
    @try {
        ARCH2FROSTSigningMaterial *material =
            [self signingMaterialForPath:path
                              pathLength:components.count - 1
                       taprootMerkleRoot:merkleRoot ?: NSData.data
                                   error:outError];
        if (!material) return nil;
        return [self signDigestInSerializedSession:digest
                                         material:material
                                            error:outError];
    } @finally {
        [_sessionLock unlock];
    }
}

- (nullable ARCH2FROSTSigningMaterial *)signingMaterialForPath:(const uint32_t *)path
                                                    pathLength:(size_t)pathLength
                                             taprootMerkleRoot:(nullable NSData *)merkleRoot
                                                         error:(NSError **)outError {
    if (merkleRoot && merkleRoot.length != 0 && merkleRoot.length != 32) {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"Taproot merkle root must be 32 bytes");
        return nil;
    }

    unsigned char group[33] = {0};
    unsigned char participantA[33] = {0};
    unsigned char participantB[33] = {0};
    unsigned char derivedGroup[33] = {0};
    unsigned char derivationTweak[32] = {0};
    memcpy(group, self.wallet.groupPublicKey.bytes, sizeof(group));
    memcpy(participantA, self.wallet.participantPublicKeyA.bytes, sizeof(participantA));
    memcpy(participantB, self.wallet.participantPublicKeyB.bytes, sizeof(participantB));

    BOOL ok = derivePublicKeyAndTweak(self.wallet.groupPublicKey,
                                      self.wallet.chainCode,
                                      path,
                                      pathLength,
                                      derivedGroup,
                                      derivationTweak);
    if (ok) {
        memcpy(group, derivedGroup, sizeof(group));
        ok = tweakPublicKey(participantA, derivationTweak) &&
            tweakPublicKey(participantB, derivationTweak);
    }

    BOOL negateAfterDerivation = NO;
    if (ok && group[0] == 0x03) {
        ok = negatePublicKey(group) &&
            negatePublicKey(participantA) &&
            negatePublicKey(participantB);
        negateAfterDerivation = ok;
    }

    unsigned char taprootTweak[32] = {0};
    BOOL hasTaprootTweak = merkleRoot != nil;
    if (ok && hasTaprootTweak) {
        unsigned char preimage[64] = {0};
        memcpy(preimage, group + 1, 32);
        NSUInteger preimageLength = 32;
        if (merkleRoot.length == 32) {
            memcpy(preimage + 32, merkleRoot.bytes, 32);
            preimageLength = 64;
        }
        ok = wally_bip340_tagged_hash(preimage, preimageLength,
                                      "TapTweak",
                                      taprootTweak,
                                      sizeof(taprootTweak)) == WALLY_OK &&
            wally_ec_scalar_verify(taprootTweak,
                                   sizeof(taprootTweak)) == WALLY_OK &&
            tweakPublicKey(group, taprootTweak) &&
            tweakPublicKey(participantA, taprootTweak) &&
            tweakPublicKey(participantB, taprootTweak);
        secureWipe(preimage, sizeof(preimage));
    }

    BOOL negateAfterTaproot = NO;
    if (ok && hasTaprootTweak && group[0] == 0x03) {
        ok = negatePublicKey(group) &&
            negatePublicKey(participantA) &&
            negatePublicKey(participantB);
        negateAfterTaproot = ok;
    }

    ARCH2FROSTSigningMaterial *material = nil;
    if (ok) {
        material = [[ARCH2FROSTSigningMaterial alloc]
            initWithParticipantPublicKeyA:[NSData dataWithBytes:participantA length:33]
                    participantPublicKeyB:[NSData dataWithBytes:participantB length:33]
                           groupPublicKey:[NSData dataWithBytes:group length:33]
                        derivationTweak:[NSData dataWithBytes:derivationTweak length:32]
                  negateAfterDerivation:negateAfterDerivation
                           taprootTweak:hasTaprootTweak
                               ? [NSData dataWithBytes:taprootTweak length:32]
                               : NSData.data
                     negateAfterTaproot:negateAfterTaproot];
    } else {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                       @"Could not derive FROST signing material");
    }
    secureWipe(group, sizeof(group));
    secureWipe(participantA, sizeof(participantA));
    secureWipe(participantB, sizeof(participantB));
    secureWipe(derivedGroup, sizeof(derivedGroup));
    secureWipe(derivationTweak, sizeof(derivationTweak));
    secureWipe(taprootTweak, sizeof(taprootTweak));
    return material;
}

- (nullable NSData *)signDigestInSerializedSession:(NSData *)digest
                                          material:(ARCH2FROSTSigningMaterial *)material
                                             error:(NSError **)outError {
    HardenedBuffer *shareA = [HardenedBuffer bufferWithLength:32 error:outError];
    HardenedBuffer *shareB = [HardenedBuffer bufferWithLength:32 error:outError];
    NSUInteger nonceStorageLength = sizeof(secp256k1_frost_nonce) + kNonceSeedLength;
    HardenedBuffer *nonceA = [HardenedBuffer bufferWithLength:nonceStorageLength
                                                        error:outError];
    HardenedBuffer *nonceB = [HardenedBuffer bufferWithLength:nonceStorageLength
                                                        error:outError];
    if (!shareA || !shareB || !nonceA || !nonceB) return nil;

    secp256k1_frost_nonce_commitment commitments[2];
    secp256k1_frost_signature_share signatureShares[2];
    secp256k1_frost_pubkey publicKeys[2];
    secp256k1_frost_keypair keypair;
    unsigned char signature[kSignatureLength];
    memset(commitments, 0, sizeof(commitments));
    memset(signatureShares, 0, sizeof(signatureShares));
    memset(publicKeys, 0, sizeof(publicKeys));
    memset(&keypair, 0, sizeof(keypair));
    memset(signature, 0, sizeof(signature));

    BOOL success = NO;
    @try {
        if (![self createNonceForParticipant:ARCH2FROSTParticipantA
                                    material:material
                                 shareBuffer:shareA
                                 nonceBuffer:nonceA
                                  commitment:&commitments[0]
                                       error:outError]) {
            return nil;
        }
        if (shareA.state != HardenedBufferStateMasked ||
            nonceA.state != HardenedBufferStateMasked) {
            setEngineError(outError,
                           ARCH2FROSTSigningEngineErrorMemoryProtectionFailed,
                           @"Participant A material was not sealed before participant B");
            return nil;
        }

        if (![self createAndSignParticipantBForDigest:digest
                                             material:material
                                          shareBuffer:shareB
                                          nonceBuffer:nonceB
                                          commitments:commitments
                                       signatureShare:&signatureShares[1]
                                                error:outError]) {
            return nil;
        }
        if (shareB.state != HardenedBufferStateMasked ||
            nonceB.state != HardenedBufferStateMasked) {
            setEngineError(outError,
                           ARCH2FROSTSigningEngineErrorMemoryProtectionFailed,
                           @"Participant B material remained open after signing");
            return nil;
        }

        if (![self signParticipantAForDigest:digest
                                     material:material
                                  shareBuffer:shareA
                                  nonceBuffer:nonceA
                                  commitments:commitments
                               signatureShare:&signatureShares[0]
                                        error:outError]) {
            return nil;
        }
        if (shareA.state != HardenedBufferStateMasked ||
            nonceA.state != HardenedBufferStateMasked) {
            setEngineError(outError,
                           ARCH2FROSTSigningEngineErrorMemoryProtectionFailed,
                           @"Participant A material remained open after signing");
            return nil;
        }

        if (!loadPublicMaterial(self.library, material,
                                ARCH2FROSTParticipantA, &publicKeys[0]) ||
            !loadPublicMaterial(self.library, material,
                                ARCH2FROSTParticipantB, &publicKeys[1])) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorWalletUnavailable,
                           @"Could not load FROST public material");
            return nil;
        }
        memset(&keypair, 0, sizeof(keypair));
        keypair.public_keys = publicKeys[0];

        if (![self.library aggregateMessage:digest
                                    keypair:&keypair
                                 publicKeys:publicKeys
                                commitments:commitments
                            signatureShares:signatureShares
                                  signature:signature]) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                           @"Could not aggregate FROST signature shares");
            return nil;
        }
        if (![self.library verifySignature:signature
                                  message:digest
                                publicKey:&publicKeys[0]]) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorVerificationFailed,
                           @"Aggregated FROST signature did not verify");
            return nil;
        }

        success = YES;
        return [NSData dataWithBytes:signature length:sizeof(signature)];
    } @finally {
        [shareA wipeAndMaskWithError:NULL];
        [shareB wipeAndMaskWithError:NULL];
        [nonceA wipeAndMaskWithError:NULL];
        [nonceB wipeAndMaskWithError:NULL];
        secureWipe(&keypair, sizeof(keypair));
        secureWipe(signatureShares, sizeof(signatureShares));
        if (!success) secureWipe(signature, sizeof(signature));
    }
}

- (BOOL)createNonceForParticipant:(ARCH2FROSTParticipant)participant
                         material:(ARCH2FROSTSigningMaterial *)material
                       shareBuffer:(HardenedBuffer *)shareBuffer
                       nonceBuffer:(HardenedBuffer *)nonceBuffer
                        commitment:(secp256k1_frost_nonce_commitment *)commitment
                             error:(NSError **)outError {
    if (![self.wallet unwrapParticipant:participant
                     intoHardenedBuffer:shareBuffer
                                  error:outError]) {
        return NO;
    }
    if (![nonceBuffer unmaskWithError:outError]) {
        [shareBuffer wipeAndMaskWithError:NULL];
        return NO;
    }

    secp256k1_frost_keypair keypair;
    memset(&keypair, 0, sizeof(keypair));
    secp256k1_frost_nonce *nonce = nonceBuffer.mutableBytes;
    unsigned char *seeds = (unsigned char *)nonce + sizeof(*nonce);
    BOOL ok = NO;
    @try {
        if (!loadKeypair(self.library, material, participant,
                         shareBuffer.mutableBytes, &keypair)) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorWalletUnavailable,
                           @"Could not load a participant FROST keypair");
            return NO;
        }
        if (SecRandomCopyBytes(kSecRandomDefault, kNonceSeedLength, seeds) !=
            errSecSuccess) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorRandomFailed,
                           @"Could not generate FROST nonce seeds");
            return NO;
        }
        if (![self.library initializeNonce:nonce
                                  keypair:&keypair
                              bindingSeed:seeds
                               hidingSeed:seeds + 32]) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                           @"Could not initialize a guarded FROST nonce");
            return NO;
        }
        secureWipe(seeds, kNonceSeedLength);
        memcpy(commitment, &nonce->commitments, sizeof(*commitment));
        ok = [nonceBuffer maskWithError:outError];
        return ok;
    } @finally {
        secureWipe(&keypair, sizeof(keypair));
        [shareBuffer wipeAndMaskWithError:NULL];
        if (!ok && nonceBuffer.state == HardenedBufferStateUnmasked) {
            [nonceBuffer wipeAndMaskWithError:NULL];
        }
    }
}

- (BOOL)createAndSignParticipantBForDigest:(NSData *)digest
                                  material:(ARCH2FROSTSigningMaterial *)material
                               shareBuffer:(HardenedBuffer *)shareBuffer
                               nonceBuffer:(HardenedBuffer *)nonceBuffer
                               commitments:(secp256k1_frost_nonce_commitment *)commitments
                            signatureShare:(secp256k1_frost_signature_share *)signatureShare
                                     error:(NSError **)outError {
    if (![self createNonceForParticipant:ARCH2FROSTParticipantB
                                material:material
                             shareBuffer:shareBuffer
                             nonceBuffer:nonceBuffer
                              commitment:&commitments[1]
                                   error:outError]) {
        return NO;
    }
    return [self signParticipant:ARCH2FROSTParticipantB
                           digest:digest
                         material:material
                      shareBuffer:shareBuffer
                      nonceBuffer:nonceBuffer
                      commitments:commitments
                   signatureShare:signatureShare
                            error:outError];
}

- (BOOL)signParticipantAForDigest:(NSData *)digest
                          material:(ARCH2FROSTSigningMaterial *)material
                       shareBuffer:(HardenedBuffer *)shareBuffer
                       nonceBuffer:(HardenedBuffer *)nonceBuffer
                       commitments:(secp256k1_frost_nonce_commitment *)commitments
                    signatureShare:(secp256k1_frost_signature_share *)signatureShare
                             error:(NSError **)outError {
    return [self signParticipant:ARCH2FROSTParticipantA
                           digest:digest
                         material:material
                      shareBuffer:shareBuffer
                      nonceBuffer:nonceBuffer
                      commitments:commitments
                   signatureShare:signatureShare
                            error:outError];
}

- (BOOL)signParticipant:(ARCH2FROSTParticipant)participant
                 digest:(NSData *)digest
               material:(ARCH2FROSTSigningMaterial *)material
            shareBuffer:(HardenedBuffer *)shareBuffer
            nonceBuffer:(HardenedBuffer *)nonceBuffer
            commitments:(secp256k1_frost_nonce_commitment *)commitments
         signatureShare:(secp256k1_frost_signature_share *)signatureShare
                  error:(NSError **)outError {
    if (![self.wallet unwrapParticipant:participant
                     intoHardenedBuffer:shareBuffer
                                  error:outError]) {
        return NO;
    }
    if (![nonceBuffer unmaskWithError:outError]) {
        [shareBuffer wipeAndMaskWithError:NULL];
        return NO;
    }

    secp256k1_frost_keypair keypair;
    memset(&keypair, 0, sizeof(keypair));
    BOOL signedShare = NO;
    @try {
        if (!loadKeypair(self.library, material, participant,
                         shareBuffer.mutableBytes, &keypair)) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorWalletUnavailable,
                           @"Could not reload a participant FROST keypair");
            return NO;
        }
        signedShare = [self.library signMessage:digest
                                        keypair:&keypair
                                          nonce:nonceBuffer.mutableBytes
                                    commitments:commitments
                                 signatureShare:signatureShare];
        if (!signedShare) {
            setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                           @"Could not create a FROST signature share");
        }
        return signedShare;
    } @finally {
        secureWipe(&keypair, sizeof(keypair));
        [nonceBuffer wipeAndMaskWithError:NULL];
        [shareBuffer wipeAndMaskWithError:NULL];
    }
}

- (nullable NSData *)signedTaprootPSBT:(NSData *)psbtData
                                 error:(NSError **)outError {
    if (psbtData.length == 0) {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"PSBT data must not be empty");
        return nil;
    }

    struct wally_psbt *psbt = NULL;
    struct wally_tx *transaction = NULL;
    int result = wally_psbt_from_bytes(psbtData.bytes,
                                       psbtData.length,
                                       WALLY_PSBT_PARSE_FLAG_STRICT,
                                       &psbt);
    if (result != WALLY_OK || !psbt) {
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"Could not parse Taproot PSBT");
        return nil;
    }
    result = wally_psbt_get_global_tx_alloc(psbt, &transaction);
    if (result != WALLY_OK || !transaction) {
        wally_psbt_free(psbt);
        setEngineError(outError, ARCH2FROSTSigningEngineErrorInvalidMessage,
                       @"Taproot PSBT has no unsigned transaction");
        return nil;
    }

    unsigned char fingerprintHash[HASH160_LEN] = {0};
    if (wally_hash160(self.wallet.groupPublicKey.bytes,
                      self.wallet.groupPublicKey.length,
                      fingerprintHash,
                      sizeof(fingerprintHash)) != WALLY_OK) {
        wally_tx_free(transaction);
        wally_psbt_free(psbt);
        setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                       @"Could not compute the ARCH-2 root fingerprint");
        return nil;
    }

    NSUInteger signaturesAdded = 0;
    [_sessionLock lock];
    @try {
        for (size_t inputIndex = 0; inputIndex < psbt->num_inputs; inputIndex++) {
            struct wally_psbt_input *input = &psbt->inputs[inputIndex];
            size_t existingSignatureLength = 0;
            if (wally_psbt_get_input_taproot_signature_len(
                    psbt, inputIndex, &existingSignatureLength) != WALLY_OK ||
                existingSignatureLength != 0) {
                continue;
            }

            for (size_t keyIndex = 0;
                 keyIndex < input->taproot_leaf_paths.num_items;
                 keyIndex++) {
                struct wally_map_item *keypath =
                    &input->taproot_leaf_paths.items[keyIndex];
                const struct wally_map_item *leafHashes =
                    wally_map_get(&input->taproot_leaf_hashes,
                                  keypath->key,
                                  keypath->key_len);
                if (keypath->key_len != 32 || keypath->value_len < 4 ||
                    memcmp(keypath->value, fingerprintHash, 4) != 0 ||
                    !leafHashes || leafHashes->value_len != 0) {
                    continue;
                }

                size_t pathLength = 0;
                if (wally_keypath_get_path_len(keypath->value,
                                               keypath->value_len,
                                               &pathLength) != WALLY_OK) {
                    continue;
                }
                uint32_t *path = pathLength > 0
                    ? calloc(pathLength, sizeof(*path)) : NULL;
                if (pathLength > 0 && !path) {
                    setEngineError(outError,
                                   ARCH2FROSTSigningEngineErrorSigningFailed,
                                   @"Could not allocate Taproot derivation path");
                    break;
                }
                size_t writtenPathLength = 0;
                if (wally_keypath_get_path(keypath->value,
                                           keypath->value_len,
                                           path,
                                           pathLength,
                                           &writtenPathLength) != WALLY_OK ||
                    writtenPathLength != pathLength) {
                    free(path);
                    continue;
                }

                unsigned char internalPublicKey[33] = {0};
                unsigned char derivationTweak[32] = {0};
                BOOL derived = derivePublicKeyAndTweak(
                    self.wallet.groupPublicKey,
                    self.wallet.chainCode,
                    path,
                    pathLength,
                    internalPublicKey,
                    derivationTweak
                );
                secureWipe(derivationTweak, sizeof(derivationTweak));
                if (!derived ||
                    memcmp(internalPublicKey + 1, keypath->key, 32) != 0) {
                    secureWipe(internalPublicKey, sizeof(internalPublicKey));
                    free(path);
                    continue;
                }
                secureWipe(internalPublicKey, sizeof(internalPublicKey));

                const struct wally_map_item *merkleRootItem =
                    wally_map_get_integer(&input->psbt_fields,
                                          kPSBTInputTapMerkleRoot);
                NSData *merkleRoot = merkleRootItem
                    ? [NSData dataWithBytes:merkleRootItem->value
                                    length:merkleRootItem->value_len]
                    : NSData.data;
                ARCH2FROSTSigningMaterial *material =
                    [self signingMaterialForPath:path
                                      pathLength:pathLength
                               taprootMerkleRoot:merkleRoot
                                           error:outError];
                free(path);
                if (!material) break;

                unsigned char digest[32] = {0};
                result = wally_psbt_get_input_signature_hash(psbt,
                                                              inputIndex,
                                                              transaction,
                                                              NULL,
                                                              0,
                                                              0,
                                                              digest,
                                                              sizeof(digest));
                if (result != WALLY_OK) {
                    secureWipe(digest, sizeof(digest));
                    continue;
                }
                NSData *signature =
                    [self signDigestInSerializedSession:
                        [NSData dataWithBytes:digest length:sizeof(digest)]
                                                 material:material
                                                    error:outError];
                secureWipe(digest, sizeof(digest));
                if (!signature) break;

                NSMutableData *taprootSignature = [signature mutableCopy];
                if (input->sighash != WALLY_SIGHASH_DEFAULT) {
                    unsigned char sighash = (unsigned char)input->sighash;
                    [taprootSignature appendBytes:&sighash length:sizeof(sighash)];
                }
                result = wally_psbt_input_set_taproot_signature(
                    input,
                    taprootSignature.bytes,
                    taprootSignature.length
                );
                if (result == WALLY_OK) signaturesAdded++;
                break;
            }
        }
    } @finally {
        [_sessionLock unlock];
        secureWipe(fingerprintHash, sizeof(fingerprintHash));
    }

    if (signaturesAdded == 0) {
        wally_tx_free(transaction);
        wally_psbt_free(psbt);
        setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                       @"PSBT contains no FROST Taproot key-path inputs");
        return nil;
    }

    size_t outputLength = 0;
    result = wally_psbt_get_length(psbt, 0, &outputLength);
    NSMutableData *output = result == WALLY_OK
        ? [NSMutableData dataWithLength:outputLength] : nil;
    size_t written = 0;
    if (!output ||
        wally_psbt_to_bytes(psbt, 0,
                            output.mutableBytes, output.length,
                            &written) != WALLY_OK) {
        wally_tx_free(transaction);
        wally_psbt_free(psbt);
        setEngineError(outError, ARCH2FROSTSigningEngineErrorSigningFailed,
                       @"Could not serialize FROST-signed Taproot PSBT");
        return nil;
    }
    output.length = written;
    wally_tx_free(transaction);
    wally_psbt_free(psbt);
    return output;
}

@end
