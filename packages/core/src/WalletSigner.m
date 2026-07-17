/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletSigner.h"

#import "HardenedShareWindow.h"
#import "SecureWipe.h"
#import "WalletPublicKeyDerivation.h"
#import "WalletShareEnvelope.h"

#import <Security/Security.h>
#import <dispatch/dispatch.h>
#import <secp256k1.h>

#include <KeccakHash.h>
#include <string.h>
#include <wally_bip32.h>
#include <wally_core.h>
#include <wally_crypto.h>
#include <wally_map.h>
#include <wally_psbt.h>
#include <wally_psbt_members.h>
#include <wally_transaction.h>

NSString * const WalletSignerErrorDomain = @"macwlt.WalletSigner";

static const NSUInteger kScalarSize = 32;
static const NSUInteger kCompressedPublicKeySize = 33;
static const NSUInteger kCompactSignatureSize = 64;
static const NSUInteger kEthereumSignatureSize = 65;

static const uint8_t kSecp256k1Order[kScalarSize] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b,
    0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
};

static const uint8_t kSecp256k1OrderMinusTwo[kScalarSize] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b,
    0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x3f,
};

static NSError *signerError(WalletSignerErrorCode code, NSString *message) {
    return [NSError errorWithDomain:WalletSignerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setSignerError(NSError **outError,
                           WalletSignerErrorCode code,
                           NSString *message) {
    if (outError) *outError = signerError(code, message);
}

static NSString *messageForNSError(NSError *error) {
    if (!error) return nil;
    NSString *description = error.localizedDescription;
    if (description.length > 0) return description;
    return [NSString stringWithFormat:@"%@ (%ld)", error.domain, (long)error.code];
}

static WalletSignerErrorCode signerErrorCodeForPublicDerivationError(NSError *error) {
    if (![error.domain isEqualToString:WalletPublicKeyDerivationErrorDomain]) {
        return WalletSignerErrorInternal;
    }

    switch (error.code) {
        case WalletPublicKeyDerivationErrorInvalidRootPublicKey:
        case WalletPublicKeyDerivationErrorInvalidChainCode:
        case WalletPublicKeyDerivationErrorInvalidPath:
            return WalletSignerErrorInvalidInput;
        case WalletPublicKeyDerivationErrorUnsupportedHardenedPath:
            return WalletSignerErrorUnsupported;
        case WalletPublicKeyDerivationErrorDerivationFailed:
        case WalletPublicKeyDerivationErrorRandomFailed:
            return WalletSignerErrorInternal;
    }
    NSCAssert(NO, @"Unhandled public derivation error code");
    return WalletSignerErrorInternal;
}

static BOOL derivationPathContainsHardenedComponent(NSString *derivationPath) {
    NSArray<NSString *> *components = [derivationPath componentsSeparatedByString:@"/"];
    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *component = components[i];
        if ([component hasSuffix:@"'"] ||
            [component hasSuffix:@"h"] ||
            [component hasSuffix:@"H"]) {
            return YES;
        }
    }
    return NO;
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
    secp256k1_context *ctx = ensureWallyInitialized() ? wally_get_secp_context() : NULL;
    if (!ctx) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Could not initialize secp256k1 context");
    }
    return ctx;
}

static int scalarCompare(const uint8_t a[kScalarSize],
                         const uint8_t b[kScalarSize]) {
    for (NSUInteger i = 0; i < kScalarSize; i++) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    return 0;
}

static BOOL scalarIsZero(const uint8_t scalar[kScalarSize]) {
    uint8_t accumulator = 0;
    for (NSUInteger i = 0; i < kScalarSize; i++) accumulator |= scalar[i];
    return accumulator == 0;
}

static void scalarSubtractOrder(uint8_t scalar[kScalarSize]) {
    uint16_t borrow = 0;
    for (NSInteger i = kScalarSize - 1; i >= 0; i--) {
        uint16_t lhs = scalar[i];
        uint16_t rhs = kSecp256k1Order[i] + borrow;
        if (lhs < rhs) {
            scalar[i] = (uint8_t)(lhs + 256 - rhs);
            borrow = 1;
        } else {
            scalar[i] = (uint8_t)(lhs - rhs);
            borrow = 0;
        }
    }
}

static BOOL scalarReduce32(const uint8_t input[kScalarSize],
                           uint8_t output[kScalarSize]) {
    memcpy(output, input, kScalarSize);
    if (scalarCompare(output, kSecp256k1Order) >= 0) scalarSubtractOrder(output);
    return !scalarIsZero(output);
}

static BOOL scalarAdd(const uint8_t a[kScalarSize],
                      const uint8_t b[kScalarSize],
                      uint8_t out[kScalarSize]) {
    uint8_t result[kScalarSize];
    BOOL ok = wally_ec_scalar_add(a, kScalarSize, b, kScalarSize, result, sizeof(result)) == WALLY_OK;
    if (ok) memcpy(out, result, kScalarSize);
    secureWipe(result, sizeof(result));
    return ok;
}

static BOOL scalarMultiply(const uint8_t a[kScalarSize],
                           const uint8_t b[kScalarSize],
                           uint8_t out[kScalarSize]) {
    uint8_t result[kScalarSize];
    BOOL ok = wally_ec_scalar_multiply(a, kScalarSize, b, kScalarSize, result, sizeof(result)) == WALLY_OK;
    if (ok) memcpy(out, result, kScalarSize);
    secureWipe(result, sizeof(result));
    return ok;
}

static BOOL scalarInverse(const uint8_t scalar[kScalarSize],
                          uint8_t out[kScalarSize]) {
    if (scalarIsZero(scalar)) return NO;

    uint8_t result[kScalarSize] = {0};
    uint8_t base[kScalarSize];
    result[kScalarSize - 1] = 1;
    memcpy(base, scalar, sizeof(base));

    for (NSUInteger byteIndex = 0; byteIndex < kScalarSize; byteIndex++) {
        uint8_t exponentByte = kSecp256k1OrderMinusTwo[byteIndex];
        for (NSInteger bit = 7; bit >= 0; bit--) {
            if (!scalarMultiply(result, result, result)) {
                secureWipe(result, sizeof(result));
                secureWipe(base, sizeof(base));
                return NO;
            }
            if (((exponentByte >> bit) & 1) != 0) {
                if (!scalarMultiply(result, base, result)) {
                    secureWipe(result, sizeof(result));
                    secureWipe(base, sizeof(base));
                    return NO;
                }
            }
        }
    }

    memcpy(out, result, kScalarSize);
    secureWipe(result, sizeof(result));
    secureWipe(base, sizeof(base));
    return YES;
}

static BOOL randomValidScalar(uint8_t out[kScalarSize]) {
    secp256k1_context *ctx = wally_get_secp_context();
    if (!ctx) return NO;

    for (NSUInteger attempt = 0; attempt < 128; attempt++) {
        if (SecRandomCopyBytes(kSecRandomDefault, kScalarSize, out) != errSecSuccess) {
            secureWipe(out, kScalarSize);
            return NO;
        }
        if (secp256k1_ec_seckey_verify(ctx, out)) return YES;
    }
    secureWipe(out, kScalarSize);
    return NO;
}

static BOOL keccak256(NSData *input, uint8_t out[kScalarSize]) {
    Keccak_HashInstance hash;
    if (Keccak_HashInitialize(&hash, 1088, 512, 256, 0x01) != KECCAK_SUCCESS) return NO;
    if (Keccak_HashUpdate(&hash, input.bytes, input.length * 8) != KECCAK_SUCCESS) return NO;
    return Keccak_HashFinal(&hash, out) == KECCAK_SUCCESS;
}

static BOOL rootExtKey(WalletShareEnvelope *shareEnvelope,
                       struct ext_key *outKey,
                       NSError **outError) {
    NSData *chainCode = shareEnvelope.chainCode;
    NSData *publicKey = shareEnvelope.jointCompressedPublicKey;
    if (chainCode.length != kScalarSize || publicKey.length != kCompressedPublicKeySize) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet chain code or root public key is unavailable");
        return NO;
    }

    int ret = bip32_key_init(BIP32_VER_MAIN_PUBLIC,
                             0,
                             0,
                             chainCode.bytes,
                             chainCode.length,
                             publicKey.bytes,
                             publicKey.length,
                             NULL,
                             0,
                             NULL,
                             0,
                             NULL,
                             0,
                             outKey);
    if (ret != WALLY_OK) {
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Could not initialize wallet root extended public key");
        return NO;
    }
    return YES;
}

static BOOL derivePublicKeyAndPrivateTweak(NSData *rootPublicKey,
                                           NSData *rootChainCode,
                                           const uint32_t *path,
                                           size_t pathLength,
                                           uint8_t outPublicKey[kCompressedPublicKeySize],
                                           uint8_t outTweak[kScalarSize],
                                           NSError **outError) {
    if (rootPublicKey.length != kCompressedPublicKeySize ||
        rootChainCode.length != kScalarSize) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet public derivation material is unavailable");
        return NO;
    }

    uint8_t currentPublicKey[kCompressedPublicKeySize];
    uint8_t currentChainCode[kScalarSize];
    uint8_t tweakSum[kScalarSize] = {0};
    memcpy(currentPublicKey, rootPublicKey.bytes, sizeof(currentPublicKey));
    memcpy(currentChainCode, rootChainCode.bytes, sizeof(currentChainCode));

    for (size_t i = 0; i < pathLength; i++) {
        uint32_t child = path[i];
        if ((child & BIP32_INITIAL_HARDENED_CHILD) != 0) {
            setSignerError(outError,
                           WalletSignerErrorUnsupported,
                           @"Hardened child signing is not available from the split root key");
            secureWipe(currentChainCode, sizeof(currentChainCode));
            secureWipe(tweakSum, sizeof(tweakSum));
            return NO;
        }

        uint8_t data[kCompressedPublicKeySize + sizeof(uint32_t)];
        memcpy(data, currentPublicKey, kCompressedPublicKeySize);
        data[33] = (uint8_t)(child >> 24);
        data[34] = (uint8_t)(child >> 16);
        data[35] = (uint8_t)(child >> 8);
        data[36] = (uint8_t)child;

        uint8_t hmac[HMAC_SHA512_LEN];
        if (wally_hmac_sha512(currentChainCode,
                              sizeof(currentChainCode),
                              data,
                              sizeof(data),
                              hmac,
                              sizeof(hmac)) != WALLY_OK ||
            wally_ec_scalar_verify(hmac, kScalarSize) != WALLY_OK) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not derive a valid non-hardened child tweak");
            secureWipe(data, sizeof(data));
            secureWipe(hmac, sizeof(hmac));
            secureWipe(currentChainCode, sizeof(currentChainCode));
            secureWipe(tweakSum, sizeof(tweakSum));
            return NO;
        }

        uint8_t nextPublicKey[kCompressedPublicKeySize];
        if (wally_ec_public_key_tweak(currentPublicKey,
                                      sizeof(currentPublicKey),
                                      hmac,
                                      kScalarSize,
                                      nextPublicKey,
                                      sizeof(nextPublicKey)) != WALLY_OK ||
            !scalarAdd(tweakSum, hmac, tweakSum)) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not derive child public key");
            secureWipe(data, sizeof(data));
            secureWipe(hmac, sizeof(hmac));
            secureWipe(currentChainCode, sizeof(currentChainCode));
            secureWipe(tweakSum, sizeof(tweakSum));
            return NO;
        }

        memcpy(currentPublicKey, nextPublicKey, sizeof(currentPublicKey));
        memcpy(currentChainCode, hmac + kScalarSize, sizeof(currentChainCode));
        secureWipe(data, sizeof(data));
        secureWipe(hmac, sizeof(hmac));
        secureWipe(nextPublicKey, sizeof(nextPublicKey));
    }

    memcpy(outPublicKey, currentPublicKey, kCompressedPublicKeySize);
    memcpy(outTweak, tweakSum, kScalarSize);
    secureWipe(currentChainCode, sizeof(currentChainCode));
    secureWipe(tweakSum, sizeof(tweakSum));
    return YES;
}

static BOOL rootFingerprint(WalletShareEnvelope *shareEnvelope,
                            uint8_t outFingerprint[4],
                            NSError **outError) {
    NSData *publicKey = shareEnvelope.jointCompressedPublicKey;
    if (publicKey.length != kCompressedPublicKeySize) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet root public key is unavailable");
        return NO;
    }

    uint8_t hash160[HASH160_LEN];
    if (wally_hash160(publicKey.bytes, publicKey.length, hash160, sizeof(hash160)) != WALLY_OK) {
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Could not compute wallet root fingerprint");
        return NO;
    }
    memcpy(outFingerprint, hash160, 4);
    secureWipe(hash160, sizeof(hash160));
    return YES;
}

@implementation WalletECDSASignature

- (instancetype)initWithCompactSignature:(NSData *)compactSignature
                            derSignature:(NSData *)derSignature
                              recoveryID:(uint8_t)recoveryID {
    NSParameterAssert(compactSignature.length == kCompactSignatureSize);
    NSParameterAssert(derSignature.length > 0);

    self = [super init];
    if (self) {
        _compactSignature = [compactSignature copy];
        _derSignature = [derSignature copy];
        _recoveryID = recoveryID;
    }
    return self;
}

@end

@interface WalletSigner () {
    WalletShareEnvelope *_shareEnvelope;
}

@end

@implementation WalletSigner

- (instancetype)init {
    self = [super init];
    return self;
}

- (nullable NSData *)bootstrapWithError:(NSError **)outError {
    NSError *error = nil;
    WalletShareEnvelope *shareEnvelope =
        [WalletShareEnvelope loadOrBootstrapFromDefaultStorageWithError:&error];
    if (!shareEnvelope) {
        if (outError) *outError = error;
        return nil;
    }

    NSData *jointPublicKey = shareEnvelope.jointCompressedPublicKey;
    if (jointPublicKey.length != kCompressedPublicKeySize) {
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Wallet root public key is unavailable");
        return nil;
    }

    _shareEnvelope = shareEnvelope;
    return [jointPublicKey copy];
}

- (nullable NSData *)publicKeyForDerivationPath:(NSString *)derivationPath
                                          error:(NSError **)outError {
    if (![derivationPath isEqualToString:@"m"] &&
        ![derivationPath hasPrefix:@"m/"]) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"Derivation path must start at m");
        return nil;
    }
    if (derivationPathContainsHardenedComponent(derivationPath)) {
        setSignerError(outError,
                       WalletSignerErrorUnsupported,
                       @"Hardened public derivation is not supported from the split root key");
        return nil;
    }
    if (!_shareEnvelope) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet material is unavailable");
        return nil;
    }

    if ([derivationPath isEqualToString:@"m"]) {
        NSData *jointPublicKey = _shareEnvelope.jointCompressedPublicKey;
        if (jointPublicKey.length != kCompressedPublicKeySize) {
            setSignerError(outError,
                           WalletSignerErrorInternal,
                           @"Wallet root public key is unavailable");
            return nil;
        }
        return [jointPublicKey copy];
    }

    NSData *jointPublicKey = _shareEnvelope.jointCompressedPublicKey;
    NSData *chainCode = _shareEnvelope.chainCode;
    if (jointPublicKey.length != kCompressedPublicKeySize ||
        chainCode.length != kScalarSize) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet public derivation material is unavailable");
        return nil;
    }

    NSError *error = nil;
    NSData *publicKey =
        [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:jointPublicKey
                                                             chainCode:chainCode
                                                        derivationPath:derivationPath
                                                                 error:&error];
    if (!publicKey) {
        setSignerError(outError,
                       signerErrorCodeForPublicDerivationError(error),
                       messageForNSError(error) ?: @"Could not derive public key");
        return nil;
    }
    return publicKey;
}

- (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                               error:(NSError **)outError {
    if (!_shareEnvelope) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet material is unavailable");
        return nil;
    }
    return [WalletSigner ethereumSignatureForTransaction:transaction
                                           shareEnvelope:_shareEnvelope
                                                   error:outError];
}

- (nullable NSData *)signedPSBTForData:(NSData *)psbtData
                                 error:(NSError **)outError {
    if (!_shareEnvelope) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"Wallet material is unavailable");
        return nil;
    }
    return [WalletSigner signedPSBTForData:psbtData
                             shareEnvelope:_shareEnvelope
                                     error:outError];
}

+ (nullable WalletECDSASignature *)signatureForDigest:(NSData *)digest32
                                               shareA:(NSData *)shareA
                                               shareB:(NSData *)shareB
                                                tweak:(NSData *)tweak
                                                error:(NSError **)outError {
    if (digest32.length != kScalarSize ||
        shareA.length != kScalarSize ||
        shareB.length != kScalarSize ||
        (tweak && tweak.length != kScalarSize)) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"ECDSA signing requires 32-byte digest, shares, and optional tweak");
        return nil;
    }

    secp256k1_context *ctx = signerContext(outError);
    if (!ctx) return nil;
    if (!secp256k1_ec_seckey_verify(ctx, shareA.bytes) ||
        !secp256k1_ec_seckey_verify(ctx, shareB.bytes) ||
        (tweak && wally_ec_scalar_verify(tweak.bytes, tweak.length) != WALLY_OK)) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"Signing share or tweak is not a valid secp256k1 scalar");
        return nil;
    }

    uint8_t digestScalar[kScalarSize];
    uint8_t kA[kScalarSize];
    uint8_t kB[kScalarSize];
    uint8_t kAInv[kScalarSize];
    uint8_t kBInv[kScalarSize];
    uint8_t r[kScalarSize];
    uint8_t rb[kScalarSize];
    uint8_t rab[kScalarSize];
    uint8_t rt[kScalarSize];
    uint8_t e[kScalarSize];
    uint8_t s[kScalarSize];
    uint8_t compact[kCompactSignatureSize];
    uint8_t normalized[kCompactSignatureSize];
    uint8_t der[EC_SIGNATURE_DER_MAX_LEN];
    size_t derLength = sizeof(der);
    memset(rt, 0, sizeof(rt));

    WalletECDSASignature *signature = nil;
    BOOL ok = NO;
    uint8_t recoveryID = 0;

    if (!scalarReduce32(digest32.bytes, digestScalar)) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"ECDSA digest reduced to zero");
        goto cleanup;
    }

    for (NSUInteger attempt = 0; attempt < 128 && !ok; attempt++) {
        if (!randomValidScalar(kA) || !randomValidScalar(kB)) {
            setSignerError(outError,
                           WalletSignerErrorUnavailable,
                           @"Could not generate ECDSA nonce shares");
            goto cleanup;
        }
        if (!scalarInverse(kA, kAInv) || !scalarInverse(kB, kBInv)) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not invert ECDSA nonce share");
            goto cleanup;
        }

        secp256k1_pubkey noncePoint;
        if (!secp256k1_ec_pubkey_create(ctx, &noncePoint, kA) ||
            !secp256k1_ec_pubkey_tweak_mul(ctx, &noncePoint, kB)) {
            continue;
        }

        uint8_t compressedNonce[33];
        uint8_t uncompressedNonce[65];
        size_t compressedNonceLength = sizeof(compressedNonce);
        size_t uncompressedNonceLength = sizeof(uncompressedNonce);
        if (!secp256k1_ec_pubkey_serialize(ctx,
                                           compressedNonce,
                                           &compressedNonceLength,
                                           &noncePoint,
                                           SECP256K1_EC_COMPRESSED) ||
            !secp256k1_ec_pubkey_serialize(ctx,
                                           uncompressedNonce,
                                           &uncompressedNonceLength,
                                           &noncePoint,
                                           SECP256K1_EC_UNCOMPRESSED)) {
            secureWipe(compressedNonce, sizeof(compressedNonce));
            secureWipe(uncompressedNonce, sizeof(uncompressedNonce));
            continue;
        }

        recoveryID = (uint8_t)(compressedNonce[0] == 0x03 ? 1 : 0);
        if (scalarCompare(uncompressedNonce + 1, kSecp256k1Order) >= 0) {
            recoveryID |= 2;
        }
        if (!scalarReduce32(uncompressedNonce + 1, r)) {
            secureWipe(compressedNonce, sizeof(compressedNonce));
            secureWipe(uncompressedNonce, sizeof(uncompressedNonce));
            continue;
        }
        secureWipe(compressedNonce, sizeof(compressedNonce));
        secureWipe(uncompressedNonce, sizeof(uncompressedNonce));

        if (!scalarMultiply(r, shareB.bytes, rb) ||
            !scalarMultiply(rb, shareA.bytes, rab)) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not compose split-key ECDSA scalar");
            goto cleanup;
        }
        if (tweak) {
            if (!scalarMultiply(r, tweak.bytes, rt)) {
                setSignerError(outError,
                               WalletSignerErrorSigningFailed,
                               @"Could not apply child-key ECDSA tweak");
                goto cleanup;
            }
        }
        if (!scalarAdd(rab, rt, e) ||
            !scalarAdd(e, digestScalar, e) ||
            !scalarMultiply(e, kBInv, s) ||
            !scalarMultiply(s, kAInv, s) ||
            scalarIsZero(s)) {
            continue;
        }

        memcpy(compact, r, kScalarSize);
        memcpy(compact + kScalarSize, s, kScalarSize);
        if (wally_ec_sig_normalize(compact,
                                   sizeof(compact),
                                   normalized,
                                   sizeof(normalized)) != WALLY_OK ||
            wally_ec_sig_to_der(normalized,
                                sizeof(normalized),
                                der,
                                sizeof(der),
                                &derLength) != WALLY_OK) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not encode ECDSA signature");
            goto cleanup;
        }
        if (memcmp(compact + kScalarSize, normalized + kScalarSize, kScalarSize) != 0) {
            recoveryID ^= 1;
        }
        ok = YES;
    }

    if (!ok) {
        setSignerError(outError,
                       WalletSignerErrorSigningFailed,
                       @"Could not produce a valid ECDSA signature");
        goto cleanup;
    }

    signature = [[WalletECDSASignature alloc]
        initWithCompactSignature:[NSData dataWithBytes:normalized length:sizeof(normalized)]
                    derSignature:[NSData dataWithBytes:der length:derLength]
                      recoveryID:recoveryID];

cleanup:
    secureWipe(digestScalar, sizeof(digestScalar));
    secureWipe(kA, sizeof(kA));
    secureWipe(kB, sizeof(kB));
    secureWipe(kAInv, sizeof(kAInv));
    secureWipe(kBInv, sizeof(kBInv));
    secureWipe(r, sizeof(r));
    secureWipe(rb, sizeof(rb));
    secureWipe(rab, sizeof(rab));
    secureWipe(rt, sizeof(rt));
    secureWipe(e, sizeof(e));
    secureWipe(s, sizeof(s));
    secureWipe(compact, sizeof(compact));
    secureWipe(normalized, sizeof(normalized));
    secureWipe(der, sizeof(der));
    return signature;
}

+ (nullable WalletECDSASignature *)signatureForDigest:(NSData *)digest32
                                        shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                                tweak:(NSData *)tweak
                                                error:(NSError **)outError {
    NSParameterAssert(shareEnvelope);
    if (digest32.length != kScalarSize || (tweak && tweak.length != kScalarSize)) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"ECDSA signing requires a 32-byte digest and optional tweak");
        return nil;
    }
    if (tweak && wally_ec_scalar_verify(tweak.bytes, tweak.length) != WALLY_OK) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"Signing tweak is not a valid secp256k1 scalar");
        return nil;
    }

    HardenedShareWindow *shareWindow = [HardenedShareWindow windowWithShareLength:kScalarSize
                                                                            error:outError];
    if (!shareWindow) return nil;

    secp256k1_context *ctx = signerContext(outError);
    if (!ctx) return nil;

    uint8_t digestScalar[kScalarSize];
    uint8_t kA[kScalarSize];
    uint8_t kB[kScalarSize];
    uint8_t kAInv[kScalarSize];
    uint8_t kBInv[kScalarSize];
    uint8_t r[kScalarSize];
    uint8_t rb[kScalarSize];
    uint8_t rab[kScalarSize];
    uint8_t rt[kScalarSize];
    uint8_t e[kScalarSize];
    uint8_t s[kScalarSize];
    uint8_t compact[kCompactSignatureSize];
    uint8_t normalized[kCompactSignatureSize];
    uint8_t der[EC_SIGNATURE_DER_MAX_LEN];
    size_t derLength = sizeof(der);
    uint8_t recoveryID = 0;
    memset(rt, 0, sizeof(rt));

    WalletECDSASignature *signature = nil;
    BOOL ok = NO;

    if (!scalarReduce32(digest32.bytes, digestScalar)) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"ECDSA digest reduced to zero");
        goto cleanup;
    }

    for (NSUInteger attempt = 0; attempt < 8 && !ok; attempt++) {
        if (!randomValidScalar(kA) || !randomValidScalar(kB) ||
            !scalarInverse(kA, kAInv) || !scalarInverse(kB, kBInv)) {
            setSignerError(outError,
                           WalletSignerErrorUnavailable,
                           @"Could not generate ECDSA nonce shares");
            goto cleanup;
        }

        secp256k1_pubkey noncePoint;
        if (!secp256k1_ec_pubkey_create(ctx, &noncePoint, kA) ||
            !secp256k1_ec_pubkey_tweak_mul(ctx, &noncePoint, kB)) {
            continue;
        }

        uint8_t compressedNonce[33];
        uint8_t uncompressedNonce[65];
        size_t compressedNonceLength = sizeof(compressedNonce);
        size_t uncompressedNonceLength = sizeof(uncompressedNonce);
        if (!secp256k1_ec_pubkey_serialize(ctx,
                                           compressedNonce,
                                           &compressedNonceLength,
                                           &noncePoint,
                                           SECP256K1_EC_COMPRESSED) ||
            !secp256k1_ec_pubkey_serialize(ctx,
                                           uncompressedNonce,
                                           &uncompressedNonceLength,
                                           &noncePoint,
                                           SECP256K1_EC_UNCOMPRESSED)) {
            secureWipe(compressedNonce, sizeof(compressedNonce));
            secureWipe(uncompressedNonce, sizeof(uncompressedNonce));
            continue;
        }

        recoveryID = (uint8_t)(compressedNonce[0] == 0x03 ? 1 : 0);
        if (scalarCompare(uncompressedNonce + 1, kSecp256k1Order) >= 0) recoveryID |= 2;
        if (!scalarReduce32(uncompressedNonce + 1, r)) {
            secureWipe(compressedNonce, sizeof(compressedNonce));
            secureWipe(uncompressedNonce, sizeof(uncompressedNonce));
            continue;
        }
        secureWipe(compressedNonce, sizeof(compressedNonce));
        secureWipe(uncompressedNonce, sizeof(uncompressedNonce));

        uint8_t *rbBytes = rb;
        uint8_t *rabBytes = rab;
        const uint8_t *rBytes = r;
        if (![shareEnvelope performWithHardenedShareWindow:shareWindow
                                                 shareAUse:^BOOL(const uint8_t *shareBytes,
                                                                 NSUInteger shareLength,
                                                                 NSError **error) {
            if (shareLength != kScalarSize) {
                setSignerError(error,
                               WalletSignerErrorInternal,
                               @"Unexpected signing share A length");
                return NO;
            }
            if (!scalarMultiply(rBytes, shareBytes, rbBytes)) {
                setSignerError(error,
                               WalletSignerErrorSigningFailed,
                               @"Could not compose share A ECDSA scalar");
                return NO;
            }
            return YES;
        } shareBUse:^BOOL(const uint8_t *shareBytes,
                          NSUInteger shareLength,
                          NSError **error) {
            if (shareLength != kScalarSize) {
                setSignerError(error,
                               WalletSignerErrorInternal,
                               @"Unexpected signing share B length");
                return NO;
            }
            if (!scalarMultiply(rbBytes, shareBytes, rabBytes)) {
                setSignerError(error,
                               WalletSignerErrorSigningFailed,
                               @"Could not compose share B ECDSA scalar");
                return NO;
            }
            return YES;
        } error:outError]) {
            goto cleanup;
        }

        if (tweak && !scalarMultiply(r, tweak.bytes, rt)) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not apply child-key ECDSA tweak");
            goto cleanup;
        }
        if (!scalarAdd(rab, rt, e) ||
            !scalarAdd(e, digestScalar, e) ||
            !scalarMultiply(e, kBInv, s) ||
            !scalarMultiply(s, kAInv, s) ||
            scalarIsZero(s)) {
            continue;
        }

        memcpy(compact, r, kScalarSize);
        memcpy(compact + kScalarSize, s, kScalarSize);
        if (wally_ec_sig_normalize(compact,
                                   sizeof(compact),
                                   normalized,
                                   sizeof(normalized)) != WALLY_OK ||
            wally_ec_sig_to_der(normalized,
                                sizeof(normalized),
                                der,
                                sizeof(der),
                                &derLength) != WALLY_OK) {
            setSignerError(outError,
                           WalletSignerErrorSigningFailed,
                           @"Could not encode ECDSA signature");
            goto cleanup;
        }
        if (memcmp(compact + kScalarSize, normalized + kScalarSize, kScalarSize) != 0) {
            recoveryID ^= 1;
        }
        ok = YES;
    }

    if (!ok) {
        setSignerError(outError,
                       WalletSignerErrorSigningFailed,
                       @"Could not produce a valid ECDSA signature");
        goto cleanup;
    }

    signature = [[WalletECDSASignature alloc]
        initWithCompactSignature:[NSData dataWithBytes:normalized length:sizeof(normalized)]
                    derSignature:[NSData dataWithBytes:der length:derLength]
                      recoveryID:recoveryID];

cleanup:
    secureWipe(digestScalar, sizeof(digestScalar));
    secureWipe(kA, sizeof(kA));
    secureWipe(kB, sizeof(kB));
    secureWipe(kAInv, sizeof(kAInv));
    secureWipe(kBInv, sizeof(kBInv));
    secureWipe(r, sizeof(r));
    secureWipe(rb, sizeof(rb));
    secureWipe(rab, sizeof(rab));
    secureWipe(rt, sizeof(rt));
    secureWipe(e, sizeof(e));
    secureWipe(s, sizeof(s));
    secureWipe(compact, sizeof(compact));
    secureWipe(normalized, sizeof(normalized));
    secureWipe(der, sizeof(der));
    return signature;
}

+ (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                      shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                              error:(NSError **)outError {
    NSParameterAssert(shareEnvelope);
    if (transaction.length == 0) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"Ethereum transaction signing preimage must not be empty");
        return nil;
    }

    uint8_t digest[kScalarSize];
    if (!keccak256(transaction, digest)) {
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Could not Keccak-hash Ethereum transaction");
        return nil;
    }

    WalletECDSASignature *signature =
        [self signatureForDigest:[NSData dataWithBytes:digest length:sizeof(digest)]
                   shareEnvelope:shareEnvelope
                           tweak:nil
                           error:outError];
    secureWipe(digest, sizeof(digest));
    if (!signature) return nil;

    NSMutableData *ethereumSignature = [signature.compactSignature mutableCopy];
    uint8_t parity = signature.recoveryID & 1;
    [ethereumSignature appendBytes:&parity length:sizeof(parity)];
    NSAssert(ethereumSignature.length == kEthereumSignatureSize,
             @"Ethereum signatures must be 65 bytes");
    return ethereumSignature;
}

+ (nullable NSData *)signedPSBTForData:(NSData *)psbtData
                         shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                 error:(NSError **)outError {
    NSParameterAssert(shareEnvelope);
    if (psbtData.length == 0) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"PSBT data must not be empty");
        return nil;
    }
    if (!ensureWallyInitialized()) {
        setSignerError(outError,
                       WalletSignerErrorUnavailable,
                       @"libwally initialization failed");
        return nil;
    }

    struct wally_psbt *psbt = NULL;
    struct wally_tx *tx = NULL;
    int ret = wally_psbt_from_bytes(psbtData.bytes,
                                    psbtData.length,
                                    WALLY_PSBT_PARSE_FLAG_STRICT,
                                    &psbt);
    if (ret != WALLY_OK) {
        setSignerError(outError,
                       WalletSignerErrorInvalidInput,
                       @"Could not parse PSBT data");
        return nil;
    }

    ret = wally_psbt_get_global_tx_alloc(psbt, &tx);
    if (ret != WALLY_OK || !tx) {
        wally_psbt_free(psbt);
        setSignerError(outError,
                       WalletSignerErrorUnsupported,
                       @"PSBT does not contain a signable unsigned transaction");
        return nil;
    }

    struct ext_key root;
    if (!rootExtKey(shareEnvelope, &root, outError)) {
        wally_tx_free(tx);
        wally_psbt_free(psbt);
        return nil;
    }

    uint8_t fingerprint[4];
    if (!rootFingerprint(shareEnvelope, fingerprint, outError)) {
        wally_tx_free(tx);
        wally_psbt_free(psbt);
        return nil;
    }

    NSUInteger signaturesAdded = 0;
    for (size_t inputIndex = 0; inputIndex < psbt->num_inputs; inputIndex++) {
        struct wally_psbt_input *input = &psbt->inputs[inputIndex];
        for (size_t keyIndex = 0; keyIndex < input->keypaths.num_items; keyIndex++) {
            struct wally_map_item *item = &input->keypaths.items[keyIndex];
            if (item->key_len != kCompressedPublicKeySize || item->value_len < 4 ||
                memcmp(item->value, fingerprint, sizeof(fingerprint)) != 0) {
                continue;
            }

            size_t pathLength = 0;
            ret = wally_keypath_get_path_len(item->value, item->value_len, &pathLength);
            if (ret != WALLY_OK) continue;

            uint32_t *path = NULL;
            if (pathLength > 0) {
                path = calloc(pathLength, sizeof(*path));
                if (!path) {
                    wally_tx_free(tx);
                    wally_psbt_free(psbt);
                    setSignerError(outError,
                                   WalletSignerErrorInternal,
                                   @"Could not allocate PSBT keypath");
                    return nil;
                }
                size_t writtenPathLength = 0;
                ret = wally_keypath_get_path(item->value,
                                             item->value_len,
                                             path,
                                             pathLength,
                                             &writtenPathLength);
                if (ret != WALLY_OK || writtenPathLength != pathLength) {
                    free(path);
                    continue;
                }
            }

            uint8_t derivedPublicKey[kCompressedPublicKeySize];
            uint8_t tweak[kScalarSize];
            BOOL derived = derivePublicKeyAndPrivateTweak(shareEnvelope.jointCompressedPublicKey,
                                                          shareEnvelope.chainCode,
                                                          path,
                                                          pathLength,
                                                          derivedPublicKey,
                                                          tweak,
                                                          outError);
            free(path);
            if (!derived) {
                wally_tx_free(tx);
                wally_psbt_free(psbt);
                return nil;
            }
            if (memcmp(derivedPublicKey, item->key, kCompressedPublicKeySize) != 0) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }

            size_t existingSignature = 0;
            ret = wally_psbt_find_input_signature(psbt,
                                                  inputIndex,
                                                  item->key,
                                                  item->key_len,
                                                  &existingSignature);
            if (ret != WALLY_OK || existingSignature != 0) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }

            size_t scriptLength = 0;
            ret = wally_psbt_get_input_signing_script_len(psbt, inputIndex, &scriptLength);
            if (ret != WALLY_OK || scriptLength == 0) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }
            NSMutableData *script = [NSMutableData dataWithLength:scriptLength];
            size_t writtenScriptLength = 0;
            ret = wally_psbt_get_input_signing_script(psbt,
                                                      inputIndex,
                                                      script.mutableBytes,
                                                      script.length,
                                                      &writtenScriptLength);
            if (ret != WALLY_OK || writtenScriptLength != script.length) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }

            size_t scriptCodeLength = 0;
            ret = wally_psbt_get_input_scriptcode_len(psbt,
                                                      inputIndex,
                                                      script.bytes,
                                                      script.length,
                                                      &scriptCodeLength);
            if (ret != WALLY_OK || scriptCodeLength == 0) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }
            NSMutableData *scriptCode = [NSMutableData dataWithLength:scriptCodeLength];
            size_t writtenScriptCodeLength = 0;
            ret = wally_psbt_get_input_scriptcode(psbt,
                                                  inputIndex,
                                                  script.bytes,
                                                  script.length,
                                                  scriptCode.mutableBytes,
                                                  scriptCode.length,
                                                  &writtenScriptCodeLength);
            if (ret != WALLY_OK || writtenScriptCodeLength != scriptCode.length) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }

            uint8_t digest[kScalarSize];
            ret = wally_psbt_get_input_signature_hash(psbt,
                                                      inputIndex,
                                                      tx,
                                                      scriptCode.bytes,
                                                      scriptCode.length,
                                                      0,
                                                      digest,
                                                      sizeof(digest));
            if (ret != WALLY_OK) {
                secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
                secureWipe(tweak, sizeof(tweak));
                continue;
            }

            WalletECDSASignature *signature =
                [self signatureForDigest:[NSData dataWithBytes:digest length:sizeof(digest)]
                           shareEnvelope:shareEnvelope
                                   tweak:[NSData dataWithBytes:tweak length:sizeof(tweak)]
                                   error:outError];
            secureWipe(digest, sizeof(digest));
            secureWipe(tweak, sizeof(tweak));
            if (!signature) {
                wally_tx_free(tx);
                wally_psbt_free(psbt);
                return nil;
            }

            NSMutableData *signatureWithSighash = [signature.derSignature mutableCopy];
            uint8_t sighash = WALLY_SIGHASH_ALL;
            uint32_t inputSighash = WALLY_SIGHASH_ALL;
            if (wally_psbt_get_input_signature_type(psbt, inputIndex, &inputSighash) == WALLY_OK &&
                inputSighash != 0) {
                sighash = (uint8_t)inputSighash;
            }
            [signatureWithSighash appendBytes:&sighash length:sizeof(sighash)];

            ret = wally_psbt_add_input_signature(psbt,
                                                 inputIndex,
                                                 item->key,
                                                 item->key_len,
                                                 signatureWithSighash.bytes,
                                                 signatureWithSighash.length);
            secureWipe(derivedPublicKey, sizeof(derivedPublicKey));
            if (ret == WALLY_OK) signaturesAdded++;
        }
    }

    if (signaturesAdded == 0) {
        wally_tx_free(tx);
        wally_psbt_free(psbt);
        setSignerError(outError,
                       WalletSignerErrorUnsupported,
                       @"PSBT contains no inputs signable by this wallet");
        return nil;
    }

    size_t outputLength = 0;
    ret = wally_psbt_get_length(psbt, 0, &outputLength);
    if (ret != WALLY_OK || outputLength == 0) {
        wally_tx_free(tx);
        wally_psbt_free(psbt);
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Could not size signed PSBT output");
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithLength:outputLength];
    size_t written = 0;
    ret = wally_psbt_to_bytes(psbt, 0, output.mutableBytes, output.length, &written);
    wally_tx_free(tx);
    wally_psbt_free(psbt);
    if (ret != WALLY_OK || written != output.length) {
        setSignerError(outError,
                       WalletSignerErrorInternal,
                       @"Could not serialize signed PSBT");
        return nil;
    }
    return output;
}

@end
