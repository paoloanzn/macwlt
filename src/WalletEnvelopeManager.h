/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

@interface WalletEnvelopeManager : NSObject

+ (NSData * _Nullable)envelopeWrap:(NSData *)secret
                         publicKey:(SecKeyRef)publicKey
                             error:(NSError * _Nullable * _Nullable)outError;

+ (NSData * _Nullable)envelopeUnwrap:(NSData *)envelope
                           privateKey:(SecKeyRef)privateKey
                               error:(NSError * _Nullable * _Nullable)outError;

+ (NSData * _Nullable)walletBootstrap:(SecKeyRef)publicKey
                                error:(NSError * _Nullable * _Nullable)outError;

// Derive a secp256k1 secret from a BIP-39 seed by walking a BIP-32 path (e.g.
// "m/84'/0'/0'/0/0"), then wrap it for the Secure Enclave public key.
+ (NSData * _Nullable)walletDeriveAndWrap:(NSData *)seed
                                     path:(NSString *)path
                                publicKey:(SecKeyRef)publicKey
                                    error:(NSError * _Nullable * _Nullable)outError;

+ (NSData * _Nullable)signWithSecp256k1:(NSData *)digest32
                                envelope:(NSData *)envelope
                                     key:(SecKeyRef)key
                                   error:(NSError * _Nullable * _Nullable)outError;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
