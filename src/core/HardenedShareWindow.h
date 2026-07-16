/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "HardenedBuffer.h"

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const HardenedShareWindowErrorDomain;

typedef NS_ENUM(NSInteger, HardenedShareWindowErrorCode) {
    HardenedShareWindowErrorInvalidShareLength = 1,
    HardenedShareWindowErrorInvalidBlock,
    HardenedShareWindowErrorUnexpectedState,
    HardenedShareWindowErrorLoaderDidNotUnmask,
};

typedef BOOL (^HardenedShareWindowLoadBlock)(HardenedBuffer *targetBuffer,
                                             NSError * _Nullable * _Nullable outError);
typedef BOOL (^HardenedShareWindowUseBlock)(const uint8_t *shareBytes,
                                            NSUInteger shareLength,
                                            NSError * _Nullable * _Nullable outError);

@interface HardenedShareWindow : NSObject

@property (nonatomic, readonly) NSUInteger shareLength;
@property (nonatomic, readonly) BOOL allMemoryLocked;
@property (nonatomic, readonly) HardenedBufferState shareAState;
@property (nonatomic, readonly) HardenedBufferState shareBState;

+ (nullable instancetype)windowWithShareLength:(NSUInteger)shareLength
                                         error:(NSError * _Nullable * _Nullable)outError;

- (nullable instancetype)initWithShareLength:(NSUInteger)shareLength
                                       error:(NSError * _Nullable * _Nullable)outError NS_DESIGNATED_INITIALIZER;

- (BOOL)performWithShareALoader:(HardenedShareWindowLoadBlock)shareALoader
                       shareAUse:(HardenedShareWindowUseBlock)shareAUse
                    shareBLoader:(HardenedShareWindowLoadBlock)shareBLoader
                       shareBUse:(HardenedShareWindowUseBlock)shareBUse
                           error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
