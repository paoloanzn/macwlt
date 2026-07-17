/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WalletService : NSObject

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)bootstrapWalletWithError:(NSError **)outError;
- (nullable NSData *)signatureForMessage:(NSString *)message
                                envelope:(NSData *)envelope
                                   error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
