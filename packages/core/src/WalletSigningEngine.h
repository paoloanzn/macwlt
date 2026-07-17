/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WalletSigningEngine <NSObject>

- (nullable NSData *)bootstrapWithError:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)publicKeyForDerivationPath:(NSString *)derivationPath
                                          error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)ethereumSignatureForTransaction:(NSData *)transaction
                                               error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)signedPSBTForData:(NSData *)psbtData
                                 error:(NSError * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
