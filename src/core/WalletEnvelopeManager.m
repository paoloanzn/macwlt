/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletEnvelopeManager.h"
#import "SecureWipe.h"

#import <dispatch/dispatch.h>
#import <secp256k1.h>
#import <string.h>
#import <wally_bip32.h>
#import <wally_core.h>

#define WALLET_ENVELOPE_ERROR_DOMAIN "app.macwlt.envelope.v1"

static const NSUInteger kSecp256k1SecretSize = 32;
static const NSUInteger kWalletBootstrapAttempts = 128;

typedef NS_ENUM(NSInteger, WalletEnvelopeErrorCode) {
    WalletEnvelopeErrorContextCreateFailed = 1,
    WalletEnvelopeErrorInvalidSecretLength,
    WalletEnvelopeErrorInvalidSecp256k1Secret,
    WalletEnvelopeErrorUnsupportedAlgorithm,
    WalletEnvelopeErrorRandomFailed,
    WalletEnvelopeErrorInvalidDigestLength,
    WalletEnvelopeErrorSigningFailed,
    WalletEnvelopeErrorDerivationFailed,
};

static SecKeyAlgorithm envelopeAlgorithm(void) {
    return kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM;
}

static NSError *envelopeError(WalletEnvelopeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:@WALLET_ENVELOPE_ERROR_DOMAIN
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setError(NSError **outError, WalletEnvelopeErrorCode code, NSString *message) {
    if (outError) *outError = envelopeError(code, message);
}

static void setCFError(NSError **outError, CFErrorRef error) {
    if (!error) return;
    if (outError) *outError = CFBridgingRelease(error);
    else CFRelease(error);
}

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
}

static secp256k1_context *secp256k1Context(NSError **outError) {
    secp256k1_context *ctx = ensureWallyInitialized() ? wally_get_secp_context() : NULL;
    if (!ctx) {
        setError(outError, WalletEnvelopeErrorContextCreateFailed,
                 @"Could not create secp256k1 context");
    }
    return ctx;
}

static BOOL validateSecp256k1Secret(NSData *secret, NSError **outError) {
    if (secret.length != kSecp256k1SecretSize) {
        setError(outError, WalletEnvelopeErrorInvalidSecretLength,
                 @"secp256k1 secret must be exactly 32 bytes");
        return NO;
    }

    secp256k1_context *ctx = secp256k1Context(outError);
    if (!ctx) return NO;

    if (!secp256k1_ec_seckey_verify(ctx, secret.bytes)) {
        setError(outError, WalletEnvelopeErrorInvalidSecp256k1Secret,
                 @"Invalid secp256k1 secret");
        return NO;
    }
    return YES;
}

static void secureClearMutableData(NSMutableData *data) {
    secureWipe(data.mutableBytes, data.length);
}

static NSMutableData *randomSecp256k1Secret(NSError **outError) {
    for (NSUInteger attempt = 0; attempt < kWalletBootstrapAttempts; attempt++) {
        NSMutableData *secret = [NSMutableData dataWithLength:kSecp256k1SecretSize];
        int status = SecRandomCopyBytes(kSecRandomDefault,
                                        kSecp256k1SecretSize,
                                        secret.mutableBytes);
        if (status != errSecSuccess) {
            secureClearMutableData(secret);
            setError(outError, WalletEnvelopeErrorRandomFailed,
                     @"Could not generate random wallet secret");
            return nil;
        }

        if (validateSecp256k1Secret(secret, NULL)) return secret;
        secureClearMutableData(secret);
    }

    setError(outError, WalletEnvelopeErrorInvalidSecp256k1Secret,
             @"Could not generate a valid secp256k1 secret");
    return nil;
}

static NSMutableData *decryptEnvelope(NSData *envelope,
                                      SecKeyRef privateKey,
                                      NSError **outError) {
    SecKeyAlgorithm algorithm = envelopeAlgorithm();
    if (!privateKey || !SecKeyIsAlgorithmSupported(privateKey,
                                                   kSecKeyOperationTypeDecrypt,
                                                   algorithm)) {
        setError(outError, WalletEnvelopeErrorUnsupportedAlgorithm,
                 @"Private key does not support ECIES envelope unwrapping");
        return nil;
    }

    CFErrorRef error = NULL;
    NSData *decrypted = CFBridgingRelease(SecKeyCreateDecryptedData(
        privateKey,
        algorithm,
        (__bridge CFDataRef)envelope,
        &error
    ));
    if (!decrypted) {
        setCFError(outError, error);
        return nil;
    }
    return [decrypted mutableCopy];
}

@implementation WalletEnvelopeManager

+ (NSData *)envelopeWrap:(NSData *)secret
               publicKey:(SecKeyRef)publicKey
                   error:(NSError **)outError {
    if (!validateSecp256k1Secret(secret, outError)) return nil;

    SecKeyAlgorithm algorithm = envelopeAlgorithm();
    if (!publicKey || !SecKeyIsAlgorithmSupported(publicKey,
                                                  kSecKeyOperationTypeEncrypt,
                                                  algorithm)) {
        setError(outError, WalletEnvelopeErrorUnsupportedAlgorithm,
                 @"Public key does not support ECIES envelope wrapping");
        return nil;
    }

    CFErrorRef error = NULL;
    NSData *envelope = CFBridgingRelease(SecKeyCreateEncryptedData(
        publicKey,
        algorithm,
        (__bridge CFDataRef)secret,
        &error
    ));
    if (!envelope) setCFError(outError, error);
    return envelope;
}

+ (NSMutableData *)envelopeUnwrap:(NSData *)envelope
                        privateKey:(SecKeyRef)privateKey
                            error:(NSError **)outError {
    NSMutableData *secret = decryptEnvelope(envelope, privateKey, outError);
    if (!secret) return nil;

    if (!validateSecp256k1Secret(secret, outError)) {
        secureClearMutableData(secret);
        return nil;
    }
    return secret;
}

+ (NSData *)walletBootstrap:(SecKeyRef)publicKey
                      error:(NSError **)outError {
    NSMutableData *secret = randomSecp256k1Secret(outError);
    if (!secret) return nil;

    NSData *envelope = nil;
    @try {
        envelope = [self envelopeWrap:secret publicKey:publicKey error:outError];
    } @finally {
        secureClearMutableData(secret);
    }
    return envelope;
}

+ (NSData *)walletDeriveAndWrap:(NSData *)seed
                          path:(NSString *)path
                     publicKey:(SecKeyRef)publicKey
                         error:(NSError **)outError {
    if (!secp256k1Context(outError)) return nil;

    const char *pathStr = path.UTF8String;
    if (!pathStr) {
        setError(outError, WalletEnvelopeErrorDerivationFailed,
                 @"BIP-32 derivation path is invalid");
        return nil;
    }

    struct ext_key root;
    struct ext_key child;
    memset(&root, 0, sizeof(root));
    memset(&child, 0, sizeof(child));

    int ret = bip32_key_from_seed(seed.bytes, seed.length,
                                  BIP32_VER_MAIN_PRIVATE, 0, &root);
    if (ret == WALLY_OK) {
        ret = bip32_key_from_parent_path_str(&root, pathStr, 0,
                                             BIP32_FLAG_KEY_PRIVATE, &child);
    }
    if (ret != WALLY_OK) {
        secureWipe(&root, sizeof(root));
        secureWipe(&child, sizeof(child));
        setError(outError, WalletEnvelopeErrorDerivationFailed,
                 @"Could not derive BIP-32 child key for path");
        return nil;
    }

    NSMutableData *secret = [NSMutableData dataWithBytes:child.priv_key + 1
                                                 length:kSecp256k1SecretSize];
    secureWipe(&root, sizeof(root));
    secureWipe(&child, sizeof(child));

    NSData *envelope = nil;
    @try {
        if (!validateSecp256k1Secret(secret, outError)) return nil;
        envelope = [self envelopeWrap:secret publicKey:publicKey error:outError];
    } @finally {
        secureClearMutableData(secret);
    }
    return envelope;
}

+ (NSData *)signWithSecp256k1:(NSData *)digest32
                      envelope:(NSData *)envelope
                           key:(SecKeyRef)key
                         error:(NSError **)outError {
    if (digest32.length != kSecp256k1SecretSize) {
        setError(outError, WalletEnvelopeErrorInvalidDigestLength,
                 @"secp256k1 digest must be exactly 32 bytes");
        return nil;
    }

    secp256k1_context *ctx = secp256k1Context(outError);
    if (!ctx) return nil;

    NSMutableData *secret = [self envelopeUnwrap:envelope privateKey:key error:outError];
    if (!secret) return nil;

    secp256k1_ecdsa_signature sig;
    int ok = secp256k1_ecdsa_sign(ctx, &sig, digest32.bytes, secret.bytes, NULL, NULL);
    secureClearMutableData(secret);
    if (!ok) {
        setError(outError, WalletEnvelopeErrorSigningFailed,
                 @"Could not sign digest with secp256k1 secret");
        return nil;
    }

    uint8_t derSig[72];
    size_t derLen = sizeof derSig;
    secp256k1_ecdsa_signature_serialize_der(ctx, derSig, &derLen, &sig);
    return [NSData dataWithBytes:derSig length:derLen];
}

@end
