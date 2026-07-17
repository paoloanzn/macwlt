/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#include <secp256k1_frost.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ARCH2FROSTLibraryErrorDomain;

typedef NS_ENUM(NSInteger, ARCH2FROSTLibraryErrorCode) {
    ARCH2FROSTLibraryErrorNotFound = 1,
    ARCH2FROSTLibraryErrorSymbolMissing,
    ARCH2FROSTLibraryErrorContextCreationFailed,
};

@interface ARCH2FROSTLibrary : NSObject

@property (nonatomic, readonly) const secp256k1_context *context;

+ (nullable instancetype)libraryWithError:(NSError * _Nullable * _Nullable)outError;
- (nullable instancetype)initWithDynamicLibraryURL:(NSURL *)dynamicLibraryURL
                                             error:(NSError * _Nullable * _Nullable)outError
    NS_DESIGNATED_INITIALIZER;

- (nullable secp256k1_frost_vss_commitments *)createVSSCommitmentsWithThreshold:(uint32_t)threshold;
- (void)destroyVSSCommitments:(nullable secp256k1_frost_vss_commitments *)commitments;
- (BOOL)beginDKGWithCommitments:(secp256k1_frost_vss_commitments *)commitments
                        shares:(secp256k1_frost_keygen_secret_share *)shares
                  participants:(uint32_t)participants
                     threshold:(uint32_t)threshold
                generatorIndex:(uint32_t)generatorIndex
                       context:(NSData *)context;
- (BOOL)validateCommitment:(secp256k1_frost_vss_commitments *)commitment
                   context:(NSData *)context;
- (BOOL)finalizeDKGForParticipant:(uint32_t)participantIndex
                          shares:(const secp256k1_frost_keygen_secret_share *)shares
                     commitments:(secp256k1_frost_vss_commitments * _Nonnull const * _Nonnull)commitments
                         keypair:(secp256k1_frost_keypair *)keypair;
- (BOOL)loadPublicKey:(secp256k1_frost_pubkey *)publicKey
                index:(uint32_t)index
         participantCount:(uint32_t)participantCount
  participantPublicKey33:(const unsigned char *)participantPublicKey33
        groupPublicKey33:(const unsigned char *)groupPublicKey33;
- (BOOL)savePublicKey:(const secp256k1_frost_pubkey *)publicKey
 participantPublicKey33:(unsigned char *)participantPublicKey33
       groupPublicKey33:(unsigned char *)groupPublicKey33;
- (BOOL)initializeNonce:(secp256k1_frost_nonce *)nonce
                keypair:(const secp256k1_frost_keypair *)keypair
            bindingSeed:(const unsigned char *)bindingSeed
             hidingSeed:(const unsigned char *)hidingSeed;
- (BOOL)signMessage:(NSData *)message
            keypair:(const secp256k1_frost_keypair *)keypair
              nonce:(secp256k1_frost_nonce *)nonce
        commitments:(secp256k1_frost_nonce_commitment *)commitments
     signatureShare:(secp256k1_frost_signature_share *)signatureShare;
- (BOOL)aggregateMessage:(NSData *)message
                 keypair:(const secp256k1_frost_keypair *)keypair
              publicKeys:(const secp256k1_frost_pubkey *)publicKeys
             commitments:(secp256k1_frost_nonce_commitment *)commitments
         signatureShares:(const secp256k1_frost_signature_share *)signatureShares
               signature:(unsigned char *)signature;
- (BOOL)verifySignature:(const unsigned char *)signature
                message:(NSData *)message
              publicKey:(const secp256k1_frost_pubkey *)publicKey;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
