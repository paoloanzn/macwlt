/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// BIP-39 mnemonic generation and seed derivation.
@interface Mnemonic : NSObject

// Generate a mnemonic for the given entropy size (128–256 bits, a multiple of
// 32). Returns nil if the entropy size is invalid or the embedded wordlist
// cannot be loaded.
+ (nullable NSArray<NSString *> *)generateWithEntropyBits:(int)entropyBits;

// Derive the 64-byte seed from a mnemonic and optional passphrase. Returns nil
// if key derivation fails.
+ (nullable NSData *)seedFromWords:(NSArray<NSString *> *)words
                        passphrase:(nullable NSString *)passphrase;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
