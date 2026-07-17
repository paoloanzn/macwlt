/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningShareSet.h"
#import "SecureWipe.h"

#import <Security/Security.h>
#import <dispatch/dispatch.h>
#import <secp256k1.h>

#include <wally_core.h>

NSString * const SigningShareSetErrorDomain = @"macwlt.SigningShareSet";

static const NSUInteger kSigningShareSize = 32;
static const NSUInteger kCompressedPublicKeySize = 33;
static const NSUInteger kShareGenerationAttempts = 128;

static NSError *shareSetError(SigningShareSetErrorCode code, NSString *message) {
    return [NSError errorWithDomain:SigningShareSetErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setShareSetError(NSError **outError,
                             SigningShareSetErrorCode code,
                             NSString *message) {
    if (outError) *outError = shareSetError(code, message);
}

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
}

static secp256k1_context *shareSetContext(NSError **outError) {
    secp256k1_context *ctx = ensureWallyInitialized() ? wally_get_secp_context() : NULL;
    if (!ctx) {
        setShareSetError(outError,
                         SigningShareSetErrorContextCreateFailed,
                         @"Could not create secp256k1 context");
    }
    return ctx;
}

static BOOL validateShare(NSData *share, NSError **outError) {
    if (share.length != kSigningShareSize) {
        setShareSetError(outError,
                         SigningShareSetErrorInvalidShareLength,
                         @"Signing share must be exactly 32 bytes");
        return NO;
    }

    secp256k1_context *ctx = shareSetContext(outError);
    if (!ctx) return NO;
    if (!secp256k1_ec_seckey_verify(ctx, share.bytes)) {
        setShareSetError(outError,
                         SigningShareSetErrorInvalidShare,
                         @"Signing share is not a valid secp256k1 scalar");
        return NO;
    }
    return YES;
}

static NSMutableData *randomShare(NSError **outError) {
    if (!shareSetContext(outError)) return nil;

    for (NSUInteger attempt = 0; attempt < kShareGenerationAttempts; attempt++) {
        NSMutableData *share = [NSMutableData dataWithLength:kSigningShareSize];
        int status = SecRandomCopyBytes(kSecRandomDefault,
                                        share.length,
                                        share.mutableBytes);
        if (status != errSecSuccess) {
            secureWipe(share.mutableBytes, share.length);
            setShareSetError(outError,
                             SigningShareSetErrorRandomFailed,
                             @"Could not generate random signing share");
            return nil;
        }

        if (validateShare(share, NULL)) return share;
        secureWipe(share.mutableBytes, share.length);
    }

    setShareSetError(outError,
                     SigningShareSetErrorInvalidShare,
                     @"Could not generate a valid secp256k1 signing share");
    return nil;
}

static NSData *jointCompressedPublicKey(NSData *shareA,
                                        NSData *shareB,
                                        NSError **outError) {
    if (!validateShare(shareA, outError)) return nil;
    if (!validateShare(shareB, outError)) return nil;

    secp256k1_context *ctx = shareSetContext(outError);
    if (!ctx) return nil;

    secp256k1_pubkey pubkey;
    if (!secp256k1_ec_pubkey_create(ctx, &pubkey, shareA.bytes) ||
        !secp256k1_ec_pubkey_tweak_mul(ctx, &pubkey, shareB.bytes)) {
        setShareSetError(outError,
                         SigningShareSetErrorJointPublicKeyFailed,
                         @"Could not compute joint secp256k1 public key");
        return nil;
    }

    uint8_t compressed[kCompressedPublicKeySize];
    size_t compressedLength = sizeof(compressed);
    int ok = secp256k1_ec_pubkey_serialize(ctx,
                                           compressed,
                                           &compressedLength,
                                           &pubkey,
                                           SECP256K1_EC_COMPRESSED);
    if (!ok || compressedLength != kCompressedPublicKeySize) {
        setShareSetError(outError,
                         SigningShareSetErrorJointPublicKeyFailed,
                         @"Could not serialize joint secp256k1 public key");
        return nil;
    }

    return [NSData dataWithBytes:compressed length:sizeof(compressed)];
}

@implementation SigningShareSet {
    NSMutableData *_shareAData;
    NSMutableData *_shareBData;
    NSData *_jointCompressedPublicKeyData;
}

+ (nullable instancetype)generateWithError:(NSError **)outError {
    NSMutableData *shareA = randomShare(outError);
    if (!shareA) return nil;

    NSMutableData *shareB = randomShare(outError);
    if (!shareB) {
        secureWipe(shareA.mutableBytes, shareA.length);
        return nil;
    }

    SigningShareSet *shareSet = [[self alloc] initWithShareA:shareA
                                                      shareB:shareB
                                                       error:outError];
    secureWipe(shareA.mutableBytes, shareA.length);
    secureWipe(shareB.mutableBytes, shareB.length);
    return shareSet;
}

+ (nullable NSData *)jointCompressedPublicKeyForShareA:(NSData *)shareA
                                               shareB:(NSData *)shareB
                                                error:(NSError **)outError {
    return jointCompressedPublicKey(shareA, shareB, outError);
}

- (nullable instancetype)initWithShareA:(NSData *)shareA
                                 shareB:(NSData *)shareB
                                  error:(NSError **)outError {
    NSData *jointPublicKey = jointCompressedPublicKey(shareA, shareB, outError);
    if (!jointPublicKey) return nil;

    self = [super init];
    if (self) {
        _shareAData = [shareA mutableCopy];
        _shareBData = [shareB mutableCopy];
        _jointCompressedPublicKeyData = [jointPublicKey copy];
    }
    return self;
}

- (void)dealloc {
    secureWipe(_shareAData.mutableBytes, _shareAData.length);
    secureWipe(_shareBData.mutableBytes, _shareBData.length);
}

- (NSData *)shareA {
    return [_shareAData copy];
}

- (NSData *)shareB {
    return [_shareBData copy];
}

- (NSData *)jointCompressedPublicKey {
    return [_jointCompressedPublicKeyData copy];
}

@end
