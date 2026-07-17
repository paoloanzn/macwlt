/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class ARCH2FROSTLibrary;
@class ARCH2FROSTWallet;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2FROSTSigningEngineErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2FROSTSigningEngineErrorCode) {
    ARCH2FROSTSigningEngineErrorInvalidMessage = 1,
    ARCH2FROSTSigningEngineErrorWalletUnavailable,
    ARCH2FROSTSigningEngineErrorMemoryProtectionFailed,
    ARCH2FROSTSigningEngineErrorRandomFailed,
    ARCH2FROSTSigningEngineErrorSigningFailed,
    ARCH2FROSTSigningEngineErrorVerificationFailed,
};

@interface ARCH2FROSTSigningEngine : NSObject

@property (nonatomic, strong, readonly) ARCH2FROSTLibrary *library;
@property (nonatomic, strong, readonly) ARCH2FROSTWallet *wallet;

+ (nullable instancetype)engineWithError:(NSError * _Nullable * _Nullable)outError;
- (instancetype)initWithLibrary:(ARCH2FROSTLibrary *)library
                         wallet:(ARCH2FROSTWallet *)wallet NS_DESIGNATED_INITIALIZER;

- (NSData *)groupPublicKey;
- (nullable NSData *)publicKeyForDerivationPath:(NSString *)derivationPath
                                          error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)signDigest:(NSData *)digest
                          error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)signTaprootDigest:(NSData *)digest
                        derivationPath:(NSString *)derivationPath
                            merkleRoot:(nullable NSData *)merkleRoot
                                 error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)signedTaprootPSBT:(NSData *)psbt
                                 error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
