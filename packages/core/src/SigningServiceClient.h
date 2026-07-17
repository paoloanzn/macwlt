/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "SigningServiceProtocol.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SigningServiceClientDefaultServiceName;

@interface SigningServiceClient : NSObject <SigningServiceProtocol>

@property (nonatomic, copy, readonly) NSString *serviceName;

+ (instancetype)clientWithDefaultService;

- (instancetype)initWithServiceName:(NSString *)serviceName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
