/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PSBTErrorDomain;

typedef NS_ENUM(NSInteger, PSBTErrorCode) {
    PSBTErrorInvalidData = 1,
    PSBTErrorInvalidPSBT = 2,
    PSBTErrorUnsupportedVersion = 3,
};

@interface PSBT : NSObject

@property (nonatomic, readonly) uint32_t version;
@property (nonatomic, readonly) NSUInteger inputCount;
@property (nonatomic, readonly) NSUInteger outputCount;

@property (nonatomic, copy, readonly, nullable) NSData *unsignedTransaction;
@property (nonatomic, copy, readonly, nullable) NSNumber *transactionVersion;
@property (nonatomic, copy, readonly, nullable) NSNumber *fallbackLocktime;
@property (nonatomic, copy, readonly, nullable) NSNumber *txModifiableFlags;

+ (nullable instancetype)psbtWithData:(NSData *)data error:(NSError **)outError;
+ (nullable instancetype)psbtWithBase64String:(NSString *)base64 error:(NSError **)outError;
+ (nullable instancetype)version0PSBTWithUnsignedTransaction:(NSData *)transaction
                                                       error:(NSError **)outError;
+ (nullable instancetype)version2PSBTWithInputCount:(NSUInteger)inputCount
                                        outputCount:(NSUInteger)outputCount
                                 transactionVersion:(uint32_t)transactionVersion
                                              error:(NSError **)outError;

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)outError;
- (BOOL)updateVersion:(uint32_t)version error:(NSError **)outError;
- (BOOL)updateUnsignedTransaction:(NSData *)unsignedTransaction error:(NSError **)outError;
- (BOOL)updateTransactionVersion:(uint32_t)transactionVersion error:(NSError **)outError;
- (BOOL)updateFallbackLocktime:(nullable NSNumber *)fallbackLocktime error:(NSError **)outError;
- (BOOL)updateTxModifiableFlags:(nullable NSNumber *)txModifiableFlags error:(NSError **)outError;
- (nullable NSData *)serializedDataWithError:(NSError **)outError;
- (nullable NSString *)base64StringWithError:(NSError **)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
