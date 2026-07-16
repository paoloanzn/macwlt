/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletService.h"

#import "SEKeyManager.h"
#import "WalletEnvelopeManager.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

#define WALLET_SERVICE_ERROR_DOMAIN "app.macwlt.wallet-service.v1"

typedef NS_ENUM(NSInteger, WalletServiceErrorCode) {
    WalletServiceErrorMissingPublicKey = 1,
    WalletServiceErrorInvalidMessageEncoding,
};

static NSError *walletServiceError(WalletServiceErrorCode code, NSString *message) {
    return [NSError errorWithDomain:@WALLET_SERVICE_ERROR_DOMAIN
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setWalletServiceError(NSError **outError,
                                  WalletServiceErrorCode code,
                                  NSString *message) {
    if (outError) *outError = walletServiceError(code, message);
}

@implementation WalletService

- (instancetype)init {
    self = [super init];
    return self;
}

- (nullable NSData *)bootstrapWalletWithError:(NSError **)outError {
    NSError *error = nil;
    SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
    if (!key) {
        if (outError) *outError = error;
        return nil;
    }

    SecKeyRef publicKey = SecKeyCopyPublicKey(key);
    if (!publicKey) {
        CFRelease(key);
        setWalletServiceError(outError,
                              WalletServiceErrorMissingPublicKey,
                              @"Could not copy Secure Enclave public key");
        return nil;
    }

    NSData *envelope = [WalletEnvelopeManager walletBootstrap:publicKey error:&error];
    CFRelease(publicKey);
    CFRelease(key);

    if (!envelope) {
        if (outError) *outError = error;
        return nil;
    }
    return envelope;
}

- (nullable NSData *)signatureForMessage:(NSString *)message
                                envelope:(NSData *)envelope
                                   error:(NSError **)outError {
    NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (!messageData) {
        setWalletServiceError(outError,
                              WalletServiceErrorInvalidMessageEncoding,
                              @"Message cannot be encoded as UTF-8");
        return nil;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(messageData.bytes, (CC_LONG)messageData.length, digest);
    NSData *digestData = [NSData dataWithBytes:digest length:sizeof(digest)];

    NSError *error = nil;
    SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
    if (!key) {
        if (outError) *outError = error;
        return nil;
    }

    NSData *signature = [WalletEnvelopeManager signWithSecp256k1:digestData
                                                        envelope:envelope
                                                             key:key
                                                           error:&error];
    CFRelease(key);

    if (!signature) {
        if (outError) *outError = error;
        return nil;
    }
    return signature;
}

@end
