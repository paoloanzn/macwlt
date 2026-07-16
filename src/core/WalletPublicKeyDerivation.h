/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WalletPublicKeyDerivationErrorDomain;

typedef NS_ENUM(NSInteger, WalletPublicKeyDerivationErrorCode) {
    WalletPublicKeyDerivationErrorInvalidRootPublicKey = 1,
    WalletPublicKeyDerivationErrorInvalidChainCode,
    WalletPublicKeyDerivationErrorInvalidPath,
    WalletPublicKeyDerivationErrorUnsupportedHardenedPath,
    WalletPublicKeyDerivationErrorDerivationFailed,
    WalletPublicKeyDerivationErrorRandomFailed,
};

@interface WalletPublicKeyDerivation : NSObject

+ (nullable NSData *)randomChainCodeWithError:(NSError * _Nullable * _Nullable)outError;
+ (nullable NSData *)publicKeyForRootCompressedPublicKey:(NSData *)rootCompressedPublicKey
                                               chainCode:(NSData *)chainCode
                                          derivationPath:(NSString *)derivationPath
                                                   error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
