/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SigningServiceBootstrapReply)(NSData * _Nullable jointPublicKey,
                                             NSError * _Nullable error);
typedef void (^SigningServicePSBTReply)(NSData * _Nullable signedPSBT,
                                        NSError * _Nullable error);
typedef void (^SigningServiceSignatureReply)(NSData * _Nullable signature,
                                             NSError * _Nullable error);
typedef void (^SigningServicePubkeyReply)(NSData * _Nullable publicKey,
                                          NSError * _Nullable error);
typedef void (^SigningServiceAttestationReply)(NSData * _Nullable attestation,
                                               NSError * _Nullable error);

@protocol SigningServiceProtocol

- (void)bootstrapWalletWithReply:(SigningServiceBootstrapReply)reply;
- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply;
- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply;
- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply;
- (void)exportAttestationForChallenge:(NSData *)challenge
                            withReply:(SigningServiceAttestationReply)reply;

@end

NS_ASSUME_NONNULL_END
