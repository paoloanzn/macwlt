/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "SigningServiceProtocol.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SigningServiceErrorDomain;

@interface SigningService : NSObject <SigningServiceProtocol>

- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)outError NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
