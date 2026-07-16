/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class WalletShareEnvelope;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const WalletSignerErrorDomain;

typedef NS_ENUM(NSInteger, WalletSignerErrorCode) {
    WalletSignerErrorInvalidInput = 1,
    WalletSignerErrorUnavailable,
    WalletSignerErrorUnsupported,
    WalletSignerErrorSigningFailed,
    WalletSignerErrorInternal,
};

@interface WalletECDSASignature : NSObject

@property (nonatomic, copy, readonly) NSData *compactSignature;
@property (nonatomic, copy, readonly) NSData *derSignature;
@property (nonatomic, readonly) uint8_t recoveryID;

- (instancetype)initWithCompactSignature:(NSData *)compactSignature
                            derSignature:(NSData *)derSignature
                              recoveryID:(uint8_t)recoveryID NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface WalletSigner : NSObject

+ (nullable WalletECDSASignature *)signatureForDigest:(NSData *)digest32
                                               shareA:(NSData *)shareA
                                               shareB:(NSData *)shareB
                                                tweak:(nullable NSData *)tweak
                                                error:(NSError * _Nullable * _Nullable)outError;

+ (nullable WalletECDSASignature *)signatureForDigest:(NSData *)digest32
                                        shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                                tweak:(nullable NSData *)tweak
                                                error:(NSError * _Nullable * _Nullable)outError;

+ (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                      shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                              error:(NSError * _Nullable * _Nullable)outError;

+ (nullable NSData *)signedPSBTForData:(NSData *)psbtData
                         shareEnvelope:(WalletShareEnvelope *)shareEnvelope
                                 error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
