/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "HardenedShareWindow.h"

@class HardenedBuffer;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WalletShareEnvelopeErrorDomain;

typedef NS_ENUM(NSInteger, WalletShareEnvelopeErrorCode) {
    WalletShareEnvelopeErrorMissingPublicKey = 1,
    WalletShareEnvelopeErrorInvalidShareLength,
    WalletShareEnvelopeErrorTargetBufferUnmasked,
    WalletShareEnvelopeErrorPersistentEnvelopeNotFound,
    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
};

typedef NS_ENUM(NSInteger, WalletShareEnvelopeShare) {
    WalletShareEnvelopeShareA = 0,
    WalletShareEnvelopeShareB,
};

@interface WalletShareEnvelope : NSObject

@property (nonatomic, copy, readonly) NSData *envelopeA;
@property (nonatomic, copy, readonly) NSData *envelopeB;
@property (nonatomic, copy, readonly) NSData *jointCompressedPublicKey;

+ (nullable instancetype)bootstrapWithError:(NSError * _Nullable * _Nullable)outError;
+ (NSURL *)defaultStorageURL;
+ (nullable instancetype)loadOrBootstrapFromDefaultStorageWithError:(NSError * _Nullable * _Nullable)outError;
+ (nullable instancetype)loadFromURL:(NSURL *)url
                                error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                         envelopeB:(NSData *)envelopeB
          jointCompressedPublicKey:(NSData *)jointCompressedPublicKey NS_DESIGNATED_INITIALIZER;

- (BOOL)writeToURL:(NSURL *)url
             error:(NSError * _Nullable * _Nullable)outError;

- (BOOL)unwrapShare:(WalletShareEnvelopeShare)share
 intoHardenedBuffer:(HardenedBuffer *)buffer
              error:(NSError * _Nullable * _Nullable)outError;

- (BOOL)performWithHardenedShareWindow:(HardenedShareWindow *)window
                              shareAUse:(HardenedShareWindowUseBlock)shareAUse
                              shareBUse:(HardenedShareWindowUseBlock)shareBUse
                                  error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
