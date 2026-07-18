/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class ARCH2ThresholdECDSALibrary;
@class HardenedBuffer;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2ThresholdECDSAWalletErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2ThresholdECDSAWalletErrorCode) {
    ARCH2ThresholdECDSAWalletErrorInvalidRecord = 1,
    ARCH2ThresholdECDSAWalletErrorNotFound,
    ARCH2ThresholdECDSAWalletErrorKeyUnavailable,
    ARCH2ThresholdECDSAWalletErrorGenerationFailed,
    ARCH2ThresholdECDSAWalletErrorInvalidParticipant,
};

typedef NS_ENUM(NSInteger, ARCH2ThresholdECDSAParticipant) {
    ARCH2ThresholdECDSAParticipantA = 1,
    ARCH2ThresholdECDSAParticipantB = 2,
};

@interface ARCH2ThresholdECDSAWallet : NSObject

@property (nonatomic, copy, readonly) NSData *envelopeA;
@property (nonatomic, copy, readonly) NSData *envelopeB;
@property (nonatomic, readonly) NSUInteger participantALength;
@property (nonatomic, readonly) NSUInteger participantBLength;
@property (nonatomic, copy, readonly) NSData *groupPublicKey;

+ (NSURL *)defaultStorageURL;
+ (nullable instancetype)loadOrCreateWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                                           error:(NSError * _Nullable * _Nullable)outError;
+ (nullable instancetype)createWithLibrary:(ARCH2ThresholdECDSALibrary *)library
                                      error:(NSError * _Nullable * _Nullable)outError;
+ (nullable instancetype)loadFromURL:(NSURL *)url
                               error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                        envelopeB:(NSData *)envelopeB
               participantALength:(NSUInteger)participantALength
               participantBLength:(NSUInteger)participantBLength
                   groupPublicKey:(NSData *)groupPublicKey NS_DESIGNATED_INITIALIZER;
- (BOOL)writeToURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)unwrapParticipant:(ARCH2ThresholdECDSAParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
