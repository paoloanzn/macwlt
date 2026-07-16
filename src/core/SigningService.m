/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningService.h"

#import "Address.h"
#import "WalletSigner.h"
#import "WalletSigningEngine.h"

#include "macwlt.h"

NSString * const SigningServiceErrorDomain = @"macwlt.SigningService";

static NSString *messageForMacwltError(macwlt_err_t error) {
    switch (error) {
        case MACWLT_OK:
            return @"No error";
        case MACWLT_ERR_INVALID_ARGUMENT:
            return @"Invalid argument";
        case MACWLT_ERR_UNAVAILABLE:
            return @"Wallet material is unavailable";
        case MACWLT_ERR_AUTH_REQUIRED:
            return @"Authentication is required";
        case MACWLT_ERR_AUTH_FAILED:
            return @"Authentication failed";
        case MACWLT_ERR_BUFFER_TOO_SMALL:
            return @"Output buffer is too small";
        case MACWLT_ERR_UNSUPPORTED:
            return @"Operation is not supported";
        case MACWLT_ERR_PARSE_FAILED:
            return @"Input parsing failed";
        case MACWLT_ERR_SIGNING_FAILED:
            return @"Signing failed";
        case MACWLT_ERR_INTERNAL:
            return @"Internal wallet error";
    }
    NSCAssert(NO, @"Unhandled macwlt error code");
    return @"Unknown wallet error";
}

static NSError *signingServiceError(macwlt_err_t error) {
    return [NSError errorWithDomain:SigningServiceErrorDomain
                               code:error
                           userInfo:@{NSLocalizedDescriptionKey: messageForMacwltError(error)}];
}

static NSString *messageForNSError(NSError *error) {
    if (!error) return nil;
    NSString *description = error.localizedDescription;
    if (description.length > 0) return description;
    return [NSString stringWithFormat:@"%@ (%ld)", error.domain, (long)error.code];
}

static NSError *signingServiceErrorWithMessage(macwlt_err_t error, NSString *message) {
    NSString *description = message.length > 0 ? message : messageForMacwltError(error);
    return [NSError errorWithDomain:SigningServiceErrorDomain
                               code:error
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static macwlt_err_t errorForSignerError(NSError *error) {
    if (![error.domain isEqualToString:WalletSignerErrorDomain]) {
        return MACWLT_ERR_INTERNAL;
    }

    switch (error.code) {
        case WalletSignerErrorInvalidInput:
            return MACWLT_ERR_INVALID_ARGUMENT;
        case WalletSignerErrorUnavailable:
            return MACWLT_ERR_UNAVAILABLE;
        case WalletSignerErrorUnsupported:
            return MACWLT_ERR_UNSUPPORTED;
        case WalletSignerErrorSigningFailed:
            return MACWLT_ERR_SIGNING_FAILED;
        case WalletSignerErrorInternal:
            return MACWLT_ERR_INTERNAL;
    }
    NSCAssert(NO, @"Unhandled signer error code");
    return MACWLT_ERR_INTERNAL;
}

static NSError *signingServiceErrorForSignerError(NSError *error) {
    macwlt_err_t serviceError = errorForSignerError(error);
    return signingServiceErrorWithMessage(serviceError, messageForNSError(error));
}

static BOOL signingServiceAddressTypeIsSupported(SigningServiceAddressType addressType) {
    switch (addressType) {
        case SigningServiceAddressTypeBitcoinP2WPKHMainnet:
        case SigningServiceAddressTypeBitcoinP2WPKHTestnet:
        case SigningServiceAddressTypeEthereum:
            return YES;
    }
    return NO;
}

static NSString *signingServiceAddressForPublicKey(NSData *publicKey,
                                                   SigningServiceAddressType addressType) {
    switch (addressType) {
        case SigningServiceAddressTypeBitcoinP2WPKHMainnet:
            return p2wpkhAddress(publicKey, YES);
        case SigningServiceAddressTypeBitcoinP2WPKHTestnet:
            return p2wpkhAddress(publicKey, NO);
        case SigningServiceAddressTypeEthereum:
            return ethereumAddress(publicKey);
    }
    NSCAssert(NO, @"Unhandled signing service address type");
    return nil;
}

@implementation SigningService {
    id<WalletSigningEngine> _signingEngine;
}

- (nullable instancetype)initWithError:(NSError **)outError {
    (void)outError;

    self = [super init];
    if (self) {
        _signingEngine = [[WalletSigner alloc] init];
    }
    return self;
}

- (void)bootstrapWalletWithReply:(SigningServiceBootstrapReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    NSData *publicKey = [_signingEngine bootstrapWithError:&error];
    if (!publicKey) {
        reply(nil, signingServiceErrorWithMessage(MACWLT_ERR_UNAVAILABLE,
                                                  messageForNSError(error)));
        return;
    }

    reply(publicKey, nil);
}

- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    NSData *signedPSBT = [_signingEngine signedPSBTForData:psbt error:&error];
    if (!signedPSBT) {
        reply(nil, signingServiceErrorForSignerError(error));
        return;
    }
    reply(signedPSBT, nil);
}

- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    NSData *signature = [_signingEngine ethereumSignatureForTransaction:transaction
                                                                  error:&error];
    if (!signature) {
        reply(nil, signingServiceErrorForSignerError(error));
        return;
    }
    reply(signature, nil);
}

- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    NSData *publicKey = [_signingEngine publicKeyForDerivationPath:derivationPath
                                                             error:&error];
    if (!publicKey) {
        reply(nil, signingServiceErrorForSignerError(error));
        return;
    }
    reply(publicKey, nil);
}

- (void)exportAddressForDerivationPath:(NSString *)derivationPath
                            addressType:(SigningServiceAddressType)addressType
                              withReply:(SigningServiceAddressReply)reply {
    NSParameterAssert(reply);

    if (!signingServiceAddressTypeIsSupported(addressType)) {
        reply(nil, signingServiceError(MACWLT_ERR_UNSUPPORTED));
        return;
    }

    NSError *error = nil;
    NSData *publicKey = [_signingEngine publicKeyForDerivationPath:derivationPath
                                                             error:&error];
    if (!publicKey) {
        reply(nil, signingServiceErrorForSignerError(error));
        return;
    }

    NSString *address = signingServiceAddressForPublicKey(publicKey, addressType);
    if (!address) {
        reply(nil, signingServiceError(MACWLT_ERR_INTERNAL));
        return;
    }
    reply(address, nil);
}

- (void)exportAttestationForChallenge:(NSData *)challenge
                            withReply:(SigningServiceAttestationReply)reply {
    NSParameterAssert(reply);
    (void)challenge;
    reply(nil, signingServiceError(MACWLT_ERR_UNSUPPORTED));
}

@end
