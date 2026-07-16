/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SEKeyPurpose) {
    SEKeyPurposeLegacyEnvelope = 0,
    SEKeyPurposeSigningShareA,
    SEKeyPurposeSigningShareB,
};

@interface SEKeyManager : NSObject

+ (BOOL)secureEnclaveAvailable;
+ (SecKeyRef _Nullable)copyKeyWithError:(NSError * _Nullable * _Nullable)outError CF_RETURNS_RETAINED;
+ (SecKeyRef _Nullable)copyKeyForPurpose:(SEKeyPurpose)purpose
                                   error:(NSError * _Nullable * _Nullable)outError CF_RETURNS_RETAINED;
+ (BOOL)deleteAllManagedKeysWithError:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
