/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WalletAddressDerivationErrorDomain;

typedef NS_ENUM(NSInteger, WalletAddressDerivationErrorCode) {
    WalletAddressDerivationErrorUnsupportedAddressType = 1,
    WalletAddressDerivationErrorAddressEncodingFailed,
};

typedef NS_ENUM(NSInteger, WalletAddressType) {
    WalletAddressTypeBitcoinP2WPKHMainnet = 1,
    WalletAddressTypeBitcoinP2WPKHTestnet,
    WalletAddressTypeEthereum,
};

@interface WalletAddressDerivation : NSObject

+ (nullable NSString *)addressForRootCompressedPublicKey:(NSData *)rootCompressedPublicKey
                                               chainCode:(NSData *)chainCode
                                          derivationPath:(NSString *)derivationPath
                                             addressType:(WalletAddressType)addressType
                                                   error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
