/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SigningShareSetErrorDomain;

typedef NS_ENUM(NSInteger, SigningShareSetErrorCode) {
    SigningShareSetErrorContextCreateFailed = 1,
    SigningShareSetErrorRandomFailed,
    SigningShareSetErrorInvalidShareLength,
    SigningShareSetErrorInvalidShare,
    SigningShareSetErrorJointPublicKeyFailed,
};

@interface SigningShareSet : NSObject

@property (nonatomic, copy, readonly) NSData *shareA;
@property (nonatomic, copy, readonly) NSData *shareB;
@property (nonatomic, copy, readonly) NSData *jointCompressedPublicKey;

+ (nullable instancetype)generateWithError:(NSError * _Nullable * _Nullable)outError;
+ (nullable NSData *)jointCompressedPublicKeyForShareA:(NSData *)shareA
                                               shareB:(NSData *)shareB
                                                error:(NSError * _Nullable * _Nullable)outError;

- (nullable instancetype)initWithShareA:(NSData *)shareA
                                 shareB:(NSData *)shareB
                                  error:(NSError * _Nullable * _Nullable)outError NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
