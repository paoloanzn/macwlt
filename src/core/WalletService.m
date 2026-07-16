/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletService.h"

#import "SEKeyManager.h"
#import "WalletEnvelopeManager.h"

#import <dispatch/dispatch.h>
#import <Security/Security.h>
#import <wally_core.h>
#import <wally_crypto.h>

#define WALLET_SERVICE_ERROR_DOMAIN "app.macwlt.wallet-service.v1"

typedef NS_ENUM(NSInteger, WalletServiceErrorCode) {
    WalletServiceErrorMissingPublicKey = 1,
    WalletServiceErrorInvalidMessageEncoding,
    WalletServiceErrorHashFailed,
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

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
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

    uint8_t digest[SHA256_LEN];
    if (!ensureWallyInitialized() ||
        wally_sha256(messageData.bytes, messageData.length,
                     digest, sizeof(digest)) != WALLY_OK) {
        setWalletServiceError(outError,
                              WalletServiceErrorHashFailed,
                              @"Could not hash message with SHA-256");
        return nil;
    }
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
