/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletAddressDerivation.h"

#import "Address.h"
#import "WalletPublicKeyDerivation.h"

NSString * const WalletAddressDerivationErrorDomain = @"macwlt.WalletAddressDerivation";

static NSError *addressDerivationError(WalletAddressDerivationErrorCode code,
                                       NSString *message) {
    return [NSError errorWithDomain:WalletAddressDerivationErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setAddressDerivationError(NSError **outError,
                                      WalletAddressDerivationErrorCode code,
                                      NSString *message) {
    if (outError) *outError = addressDerivationError(code, message);
}

@implementation WalletAddressDerivation

+ (nullable NSString *)addressForRootCompressedPublicKey:(NSData *)rootCompressedPublicKey
                                               chainCode:(NSData *)chainCode
                                          derivationPath:(NSString *)derivationPath
                                             addressType:(WalletAddressType)addressType
                                                   error:(NSError **)outError {
    if (addressType != WalletAddressTypeBitcoinP2WPKHMainnet &&
        addressType != WalletAddressTypeBitcoinP2WPKHTestnet &&
        addressType != WalletAddressTypeEthereum) {
        setAddressDerivationError(outError,
                                  WalletAddressDerivationErrorUnsupportedAddressType,
                                  @"Unsupported wallet address type");
        return nil;
    }

    NSError *derivationError = nil;
    NSData *publicKey = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootCompressedPublicKey
                                                                             chainCode:chainCode
                                                                        derivationPath:derivationPath
                                                                               error:&derivationError];
    if (!publicKey) {
        if (outError) *outError = derivationError;
        return nil;
    }

    NSString *address = nil;
    switch (addressType) {
        case WalletAddressTypeBitcoinP2WPKHMainnet:
            address = p2wpkhAddress(publicKey, YES);
            break;
        case WalletAddressTypeBitcoinP2WPKHTestnet:
            address = p2wpkhAddress(publicKey, NO);
            break;
        case WalletAddressTypeEthereum:
            address = ethereumAddress(publicKey);
            break;
    }

    if (!address) {
        setAddressDerivationError(outError,
                                  WalletAddressDerivationErrorAddressEncodingFailed,
                                  @"Could not encode wallet address from derived public key");
        return nil;
    }
    return address;
}

@end
