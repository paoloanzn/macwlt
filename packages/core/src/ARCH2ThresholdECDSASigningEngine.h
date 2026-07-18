/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class ARCH2ThresholdECDSALibrary;
@class ARCH2ThresholdECDSAWallet;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2ThresholdECDSASigningEngineErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2ThresholdECDSASigningEngineErrorCode) {
    ARCH2ThresholdECDSASigningEngineErrorInvalidTransaction = 1,
    ARCH2ThresholdECDSASigningEngineErrorWalletUnavailable,
    ARCH2ThresholdECDSASigningEngineErrorMemoryProtectionFailed,
    ARCH2ThresholdECDSASigningEngineErrorSigningFailed,
    ARCH2ThresholdECDSASigningEngineErrorRecoveryFailed,
};

@interface ARCH2ThresholdECDSASigningEngine : NSObject

@property (nonatomic, strong, readonly) ARCH2ThresholdECDSALibrary *library;
@property (nonatomic, strong, readonly) ARCH2ThresholdECDSAWallet *wallet;

+ (nullable instancetype)engineWithError:(NSError * _Nullable * _Nullable)outError;
- (instancetype)initWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                         wallet:(ARCH2ThresholdECDSAWallet *)wallet NS_DESIGNATED_INITIALIZER;

- (NSData *)groupPublicKey;
- (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                               error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
