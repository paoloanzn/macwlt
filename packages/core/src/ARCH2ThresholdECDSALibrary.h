/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2ThresholdECDSALibraryErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2ThresholdECDSALibraryErrorCode) {
    ARCH2ThresholdECDSALibraryErrorGenerationFailed = 1,
    ARCH2ThresholdECDSALibraryErrorSigningFailed,
    ARCH2ThresholdECDSALibraryErrorInvalidOutput,
};

@interface ARCH2ThresholdECDSAKeyMaterial : NSObject

@property (nonatomic, strong, readonly) NSMutableData *participantA;
@property (nonatomic, strong, readonly) NSMutableData *participantB;
@property (nonatomic, copy, readonly) NSData *groupPublicKey;

- (instancetype)initWithParticipantA:(NSMutableData *)participantA
                        participantB:(NSMutableData *)participantB
                      groupPublicKey:(NSData *)groupPublicKey NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface ARCH2ThresholdECDSALibrary : NSObject

+ (instancetype)library;

- (nullable ARCH2ThresholdECDSAKeyMaterial *)
    generateKeyMaterialWithError:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)signTransaction:(NSData *)transaction
                        participantA:(NSData *)participantA
                        participantB:(NSData *)participantB
                               error:(NSError * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
