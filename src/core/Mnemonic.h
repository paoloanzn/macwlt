/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Mnemonic : NSObject

+ (nullable NSArray<NSString *> *)generateWithEntropyBits:(int)entropyBits;

+ (nullable NSData *)seedFromWords:(NSArray<NSString *> *)words
                        passphrase:(nullable NSString *)passphrase;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
