/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningService.h"

#import "ARCH2FROSTSigningEngine.h"
#import "ARCH2FROSTWallet.h"
#import "Address.h"
#import "SEKeyManager.h"
#import "WalletShareEnvelope.h"
#import "WalletSigner.h"
#import "WalletSigningEngine.h"

#include "macwlt.h"

#include <wally_psbt.h>

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

static BOOL psbtContainsTaprootKeyPath(NSData *data) {
    struct wally_psbt *psbt = NULL;
    int result = wally_psbt_from_bytes(data.bytes,
                                       data.length,
                                       WALLY_PSBT_PARSE_FLAG_STRICT,
                                       &psbt);
    if (result != WALLY_OK || !psbt) return NO;
    BOOL containsTaproot = NO;
    for (size_t index = 0; index < psbt->num_inputs; index++) {
        if (psbt->inputs[index].taproot_leaf_paths.num_items > 0) {
            containsTaproot = YES;
            break;
        }
    }
    wally_psbt_free(psbt);
    return containsTaproot;
}

static BOOL signingServiceAddressTypeIsSupported(SigningServiceAddressType addressType) {
    switch (addressType) {
        case SigningServiceAddressTypeBitcoinP2WPKHMainnet:
        case SigningServiceAddressTypeBitcoinP2WPKHTestnet:
        case SigningServiceAddressTypeEthereum:
        case SigningServiceAddressTypeBitcoinP2TRMainnet:
        case SigningServiceAddressTypeBitcoinP2TRTestnet:
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
        case SigningServiceAddressTypeBitcoinP2TRMainnet:
            return p2trAddress(publicKey, YES);
        case SigningServiceAddressTypeBitcoinP2TRTestnet:
            return p2trAddress(publicKey, NO);
    }
    NSCAssert(NO, @"Unhandled signing service address type");
    return nil;
}

@implementation SigningService {
    id<WalletSigningEngine> _signingEngine;
    ARCH2FROSTSigningEngine *_frostSigningEngine;
}

- (nullable instancetype)initWithError:(NSError **)outError {
    (void)outError;

    self = [super init];
    if (self) {
        _signingEngine = [[WalletSigner alloc] init];
    }
    return self;
}

- (nullable ARCH2FROSTSigningEngine *)frostSigningEngineWithError:(NSError **)outError {
    if (_frostSigningEngine) return _frostSigningEngine;
    _frostSigningEngine = [ARCH2FROSTSigningEngine engineWithError:outError];
    return _frostSigningEngine;
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

- (void)bootstrapFROSTWalletWithReply:(SigningServiceBootstrapReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    ARCH2FROSTSigningEngine *engine = [self frostSigningEngineWithError:&error];
    if (!engine) {
        reply(nil, signingServiceErrorWithMessage(MACWLT_ERR_UNAVAILABLE,
                                                  messageForNSError(error)));
        return;
    }
    reply(engine.groupPublicKey, nil);
}

- (void)resetWalletWithReply:(SigningServiceResetReply)reply {
    NSParameterAssert(reply);

    _signingEngine = [[WalletSigner alloc] init];
    _frostSigningEngine = nil;
    NSArray<NSURL *> *storageURLs = @[
        WalletShareEnvelope.defaultStorageURL,
        ARCH2FROSTWallet.defaultStorageURL,
    ];
    NSError *error = nil;
    for (NSURL *url in storageURLs) {
        if ([NSFileManager.defaultManager fileExistsAtPath:url.path] &&
            ![NSFileManager.defaultManager removeItemAtURL:url error:&error]) {
            reply(NO, signingServiceErrorWithMessage(MACWLT_ERR_UNAVAILABLE,
                                                      messageForNSError(error)));
            return;
        }
    }
    if (![SEKeyManager deleteAllManagedKeysWithError:&error]) {
        reply(NO, signingServiceErrorWithMessage(MACWLT_ERR_UNAVAILABLE,
                                                  messageForNSError(error)));
        return;
    }
    reply(YES, nil);
}

- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    BOOL usesFROST = psbtContainsTaprootKeyPath(psbt);
    NSData *signedPSBT = usesFROST
        ? [[self frostSigningEngineWithError:&error]
            signedTaprootPSBT:psbt error:&error]
        : [_signingEngine signedPSBTForData:psbt error:&error];
    if (!signedPSBT) {
        macwlt_err_t code = usesFROST
            ? MACWLT_ERR_SIGNING_FAILED : errorForSignerError(error);
        reply(nil, signingServiceErrorWithMessage(code, messageForNSError(error)));
        return;
    }
    reply(signedPSBT, nil);
}

- (void)signDigest:(NSData *)digest withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);

    NSError *error = nil;
    ARCH2FROSTSigningEngine *engine = [self frostSigningEngineWithError:&error];
    NSData *signature = [engine signDigest:digest error:&error];
    if (!signature) {
        reply(nil, signingServiceErrorWithMessage(MACWLT_ERR_SIGNING_FAILED,
                                                  messageForNSError(error)));
        return;
    }
    reply(signature, nil);
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
    BOOL usesFROST = [derivationPath isEqualToString:@"m/86"] ||
        [derivationPath hasPrefix:@"m/86/"];
    NSData *publicKey = usesFROST
        ? [[self frostSigningEngineWithError:&error]
            publicKeyForDerivationPath:derivationPath error:&error]
        : [_signingEngine publicKeyForDerivationPath:derivationPath error:&error];
    if (!publicKey) {
        macwlt_err_t code = usesFROST
            ? MACWLT_ERR_UNAVAILABLE : errorForSignerError(error);
        reply(nil, signingServiceErrorWithMessage(code, messageForNSError(error)));
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
    BOOL usesFROST = addressType == SigningServiceAddressTypeBitcoinP2TRMainnet ||
        addressType == SigningServiceAddressTypeBitcoinP2TRTestnet;
    ARCH2FROSTSigningEngine *frostEngine = usesFROST
        ? [self frostSigningEngineWithError:&error] : nil;
    NSData *publicKey = usesFROST
        ? [frostEngine publicKeyForDerivationPath:derivationPath error:&error]
        : [_signingEngine publicKeyForDerivationPath:derivationPath error:&error];
    if (!publicKey) {
        macwlt_err_t code = usesFROST
            ? MACWLT_ERR_UNAVAILABLE : errorForSignerError(error);
        reply(nil, signingServiceErrorWithMessage(code, messageForNSError(error)));
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
