/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletEnvelopeManager.h"
#import "BIP32.h"

#import <dispatch/dispatch.h>
#import <secp256k1.h>
#import <string.h>

#define WALLET_ENVELOPE_ERROR_DOMAIN "app.macwlt.envelope.v1"

static const NSUInteger kSecp256k1SecretSize = 32;
static const NSUInteger kWalletBootstrapAttempts = 128;

static secp256k1_context *gCtx = NULL;

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

static secp256k1_context *secp256k1Context(NSError **outError) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCtx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN |
                                        SECP256K1_CONTEXT_VERIFY);
    });

    if (!gCtx) {
        setError(outError, WalletEnvelopeErrorContextCreateFailed,
                 @"Could not create secp256k1 context");
    }
    return gCtx;
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

static void secureClearData(NSData *data) {
    if (!data.bytes || data.length == 0) return;
    (void)memset_s((void *)data.bytes, data.length, 0, data.length);
}

static NSMutableData *randomSecp256k1Secret(NSError **outError) {
    for (NSUInteger attempt = 0; attempt < kWalletBootstrapAttempts; attempt++) {
        NSMutableData *secret = [NSMutableData dataWithLength:kSecp256k1SecretSize];
        int status = SecRandomCopyBytes(kSecRandomDefault,
                                        kSecp256k1SecretSize,
                                        secret.mutableBytes);
        if (status != errSecSuccess) {
            secureClearData(secret);
            setError(outError, WalletEnvelopeErrorRandomFailed,
                     @"Could not generate random wallet secret");
            return nil;
        }

        if (validateSecp256k1Secret(secret, NULL)) return secret;
        secureClearData(secret);
    }

    setError(outError, WalletEnvelopeErrorInvalidSecp256k1Secret,
             @"Could not generate a valid secp256k1 secret");
    return nil;
}

static NSData *decryptEnvelope(NSData *envelope,
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
    return decrypted;
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

+ (NSData *)envelopeUnwrap:(NSData *)envelope
                privateKey:(SecKeyRef)privateKey
                    error:(NSError **)outError {
    NSData *secret = decryptEnvelope(envelope, privateKey, outError);
    if (!secret) return nil;

    if (!validateSecp256k1Secret(secret, outError)) {
        secureClearData(secret);
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
        secureClearData(secret);
    }
    return envelope;
}

+ (NSData *)walletDeriveAndWrap:(NSData *)seed
                          path:(NSString *)path
                     publicKey:(SecKeyRef)publicKey
                         error:(NSError **)outError {
    secp256k1_context *ctx = secp256k1Context(outError);
    if (!ctx) return nil;

    const char *pathStr = path.UTF8String;
    if (!pathStr) {
        setError(outError, WalletEnvelopeErrorDerivationFailed,
                 @"BIP-32 derivation path is invalid");
        return nil;
    }

    // Back the node with NSMutableData so it can be wiped with secureClearData.
    NSMutableData *nodeData = [NSMutableData dataWithLength:sizeof(ExtKey)];
    ExtKey *node = nodeData.mutableBytes;
    if (!bip32Derive(ctx, seed.bytes, seed.length, pathStr, node)) {
        secureClearData(nodeData);
        setError(outError, WalletEnvelopeErrorDerivationFailed,
                 @"Could not derive BIP-32 child key for path");
        return nil;
    }

    NSMutableData *secret = [NSMutableData dataWithBytes:node->priv
                                                 length:kSecp256k1SecretSize];
    secureClearData(nodeData);

    NSData *envelope = nil;
    @try {
        if (!validateSecp256k1Secret(secret, outError)) return nil;
        envelope = [self envelopeWrap:secret publicKey:publicKey error:outError];
    } @finally {
        secureClearData(secret);
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

    NSData *secret = [self envelopeUnwrap:envelope privateKey:key error:outError];
    if (!secret) return nil;

    secp256k1_ecdsa_signature sig;
    int ok = secp256k1_ecdsa_sign(ctx, &sig, digest32.bytes, secret.bytes, NULL, NULL);
    secureClearData(secret);
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
