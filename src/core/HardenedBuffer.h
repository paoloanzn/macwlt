/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const HardenedBufferErrorDomain;

typedef NS_ENUM(NSInteger, HardenedBufferErrorCode) {
    HardenedBufferErrorInvalidLength = 1,
    HardenedBufferErrorPageSizeUnavailable,
    HardenedBufferErrorAllocationFailed,
    HardenedBufferErrorLockFailed,
    HardenedBufferErrorProtectionFailed,
};

typedef NS_ENUM(NSInteger, HardenedBufferState) {
    HardenedBufferStateMasked = 0,
    HardenedBufferStateUnmasked,
};

@interface HardenedBuffer : NSObject

@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly) BOOL memoryLocked;
@property (nonatomic, readonly) HardenedBufferState state;

+ (nullable instancetype)bufferWithLength:(NSUInteger)length
                                    error:(NSError * _Nullable * _Nullable)outError;

- (nullable instancetype)initWithLength:(NSUInteger)length
                                  error:(NSError * _Nullable * _Nullable)outError NS_DESIGNATED_INITIALIZER;

- (BOOL)unmaskWithError:(NSError * _Nullable * _Nullable)outError;
- (BOOL)maskWithError:(NSError * _Nullable * _Nullable)outError;
- (BOOL)wipeAndMaskWithError:(NSError * _Nullable * _Nullable)outError;
- (void *)mutableBytes NS_RETURNS_INNER_POINTER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
