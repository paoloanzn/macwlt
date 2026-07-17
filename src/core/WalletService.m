/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletService.h"

#import "SigningServiceClient.h"

#import <dispatch/dispatch.h>
#import <wally_core.h>
#import <wally_crypto.h>

#define WALLET_SERVICE_ERROR_DOMAIN "app.macwlt.wallet-service.v1"

typedef NS_ENUM(NSInteger, WalletServiceErrorCode) {
    WalletServiceErrorInvalidMessageEncoding = 1,
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

@implementation WalletService {
    SigningServiceClient *_client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _client = [SigningServiceClient clientWithDefaultService];
    }
    return self;
}

- (nullable NSData *)bootstrapWalletWithError:(NSError **)outError {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *publicKey = nil;
    __block NSError *operationError = nil;
    [_client bootstrapFROSTWalletWithReply:^(NSData *value, NSError *error) {
        publicKey = value;
        operationError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (!publicKey && outError) *outError = operationError;
    return publicKey;
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

    (void)envelope;
    NSData *digestData = [NSData dataWithBytes:digest length:sizeof(digest)];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *signature = nil;
    __block NSError *operationError = nil;
    [_client signDigest:digestData withReply:^(NSData *value, NSError *error) {
        signature = value;
        operationError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (!signature && outError) *outError = operationError;
    return signature;
}

@end
