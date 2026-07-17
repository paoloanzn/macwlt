/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *_Nullable p2wpkhAddress(NSData *compressedPubKey, BOOL mainnet);
NSString *_Nullable p2trAddress(NSData *compressedInternalPublicKey, BOOL mainnet);
NSString *_Nullable ethereumAddress(NSData *publicKey);

NS_ASSUME_NONNULL_END
