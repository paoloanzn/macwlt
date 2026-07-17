/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class ARCH2FROSTLibrary;
@class HardenedBuffer;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2FROSTWalletErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2FROSTWalletErrorCode) {
    ARCH2FROSTWalletErrorInvalidRecord = 1,
    ARCH2FROSTWalletErrorNotFound,
    ARCH2FROSTWalletErrorKeyUnavailable,
    ARCH2FROSTWalletErrorDKGFailed,
    ARCH2FROSTWalletErrorWrappingFailed,
    ARCH2FROSTWalletErrorInvalidShare,
};

typedef NS_ENUM(NSInteger, ARCH2FROSTParticipant) {
    ARCH2FROSTParticipantA = 1,
    ARCH2FROSTParticipantB = 2,
};

@interface ARCH2FROSTWallet : NSObject

@property (nonatomic, copy, readonly) NSData *envelopeA;
@property (nonatomic, copy, readonly) NSData *envelopeB;
@property (nonatomic, copy, readonly) NSData *participantPublicKeyA;
@property (nonatomic, copy, readonly) NSData *participantPublicKeyB;
@property (nonatomic, copy, readonly) NSData *groupPublicKey;
@property (nonatomic, copy, readonly) NSData *chainCode;

+ (NSURL *)defaultStorageURL;
+ (nullable instancetype)loadOrCreateWithLibrary:(ARCH2FROSTLibrary *)library
                                           error:(NSError * _Nullable * _Nullable)outError;
+ (nullable instancetype)createWithLibrary:(ARCH2FROSTLibrary *)library
                                      error:(NSError * _Nullable * _Nullable)outError;
+ (nullable instancetype)loadFromURL:(NSURL *)url
                               error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                        envelopeB:(NSData *)envelopeB
             participantPublicKeyA:(NSData *)participantPublicKeyA
             participantPublicKeyB:(NSData *)participantPublicKeyB
                    groupPublicKey:(NSData *)groupPublicKey
                         chainCode:(NSData *)chainCode NS_DESIGNATED_INITIALIZER;
- (BOOL)writeToURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)unwrapParticipant:(ARCH2FROSTParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
