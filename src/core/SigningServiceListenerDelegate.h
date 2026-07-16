/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SigningService;

@interface SigningServiceListenerDelegate : NSObject <NSXPCListenerDelegate>

@property (nonatomic, strong, readonly) SigningService *service;

- (instancetype)initWithService:(SigningService *)service NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
