/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#include "macwlt.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SigningServiceAddressType) {
    SigningServiceAddressTypeBitcoinP2WPKHMainnet = MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET,
    SigningServiceAddressTypeBitcoinP2WPKHTestnet = MACWLT_ADDRESS_BITCOIN_P2WPKH_TESTNET,
    SigningServiceAddressTypeEthereum = MACWLT_ADDRESS_ETHEREUM,
    SigningServiceAddressTypeBitcoinP2TRMainnet = MACWLT_ADDRESS_BITCOIN_P2TR_MAINNET,
    SigningServiceAddressTypeBitcoinP2TRTestnet = MACWLT_ADDRESS_BITCOIN_P2TR_TESTNET,
};

typedef void (^SigningServiceBootstrapReply)(NSData * _Nullable jointPublicKey,
                                             NSError * _Nullable error);
typedef void (^SigningServicePSBTReply)(NSData * _Nullable signedPSBT,
                                        NSError * _Nullable error);
typedef void (^SigningServiceSignatureReply)(NSData * _Nullable signature,
                                             NSError * _Nullable error);
typedef void (^SigningServicePubkeyReply)(NSData * _Nullable publicKey,
                                          NSError * _Nullable error);
typedef void (^SigningServiceAddressReply)(NSString * _Nullable address,
                                           NSError * _Nullable error);
typedef void (^SigningServiceAttestationReply)(NSData * _Nullable attestation,
                                               NSError * _Nullable error);
typedef void (^SigningServiceResetReply)(BOOL reset, NSError * _Nullable error);

@protocol SigningServiceProtocol <NSObject>

- (void)bootstrapWalletWithReply:(SigningServiceBootstrapReply)reply;
- (void)bootstrapFROSTWalletWithReply:(SigningServiceBootstrapReply)reply;
- (void)resetWalletWithReply:(SigningServiceResetReply)reply;
- (void)signDigest:(NSData *)digest withReply:(SigningServiceSignatureReply)reply;
- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply;
- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply;
- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply;
- (void)exportAddressForDerivationPath:(NSString *)derivationPath
                            addressType:(SigningServiceAddressType)addressType
                              withReply:(SigningServiceAddressReply)reply;
- (void)exportAttestationForChallenge:(NSData *)challenge
                            withReply:(SigningServiceAttestationReply)reply;

@end

NS_ASSUME_NONNULL_END
