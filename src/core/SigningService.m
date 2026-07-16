/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningService.h"

#include "macwlt.h"

NSString * const SigningServiceErrorDomain = @"macwlt.SigningService";

typedef int (^SigningServiceCallBlock)(uint8_t * _Nullable output,
                                       size_t *inoutOutputLength);

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

@implementation SigningService {
    macwlt_wallet_t *_wallet;
}

- (nullable instancetype)initWithError:(NSError **)outError {
    macwlt_wallet_t *wallet = NULL;
    if (macwlt_wallet_create(&wallet) != MACWLT_SUCCESS || !wallet) {
        if (outError) *outError = signingServiceError(MACWLT_ERR_INTERNAL);
        return nil;
    }

    self = [super init];
    if (self) {
        _wallet = wallet;
    } else {
        macwlt_wallet_free(wallet);
    }
    return self;
}

- (void)dealloc {
    macwlt_wallet_free(_wallet);
}

- (NSError *)lastError {
    return signingServiceError(macwlt_last_error(_wallet));
}

- (void)bootstrapWalletWithReply:(SigningServiceBootstrapReply)reply {
    NSParameterAssert(reply);

    uint8_t publicKey[33];
    size_t publicKeyLength = sizeof(publicKey);
    int status = macwlt_bootstrap_wallet(_wallet, publicKey, &publicKeyLength);
    if (status != MACWLT_SUCCESS) {
        reply(nil, [self lastError]);
        return;
    }

    reply([NSData dataWithBytes:publicKey length:publicKeyLength], nil);
}

- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply {
    NSParameterAssert(reply);
    [self dataFromDynamicCall:^int(uint8_t *output, size_t *inoutOutputLength) {
        return macwlt_sign_psbt(_wallet,
                                psbt.bytes,
                                psbt.length,
                                output,
                                inoutOutputLength);
    } reply:reply];
}

- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);
    [self dataFromDynamicCall:^int(uint8_t *output, size_t *inoutOutputLength) {
        return macwlt_sign_eth_tx(_wallet,
                                  transaction.bytes,
                                  transaction.length,
                                  output,
                                  inoutOutputLength);
    } reply:reply];
}

- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply {
    NSParameterAssert(reply);

    NSData *pathData = [derivationPath dataUsingEncoding:NSUTF8StringEncoding];
    if (!pathData) {
        reply(nil, signingServiceError(MACWLT_ERR_INVALID_ARGUMENT));
        return;
    }

    NSMutableData *nulTerminatedPath = [pathData mutableCopy];
    uint8_t nul = 0;
    [nulTerminatedPath appendBytes:&nul length:sizeof(nul)];

    [self dataFromDynamicCall:^int(uint8_t *output, size_t *inoutOutputLength) {
        return macwlt_export_pubkey(_wallet,
                                    nulTerminatedPath.bytes,
                                    output,
                                    inoutOutputLength);
    } reply:reply];
}

- (void)exportAttestationForChallenge:(NSData *)challenge
                            withReply:(SigningServiceAttestationReply)reply {
    NSParameterAssert(reply);
    [self dataFromDynamicCall:^int(uint8_t *output, size_t *inoutOutputLength) {
        return macwlt_export_attestation(_wallet,
                                         challenge.bytes,
                                         challenge.length,
                                         output,
                                         inoutOutputLength);
    } reply:reply];
}

- (void)dataFromDynamicCall:(SigningServiceCallBlock)call
                     reply:(void (^)(NSData * _Nullable data, NSError * _Nullable error))reply {
    NSParameterAssert(call);
    NSParameterAssert(reply);

    size_t outputLength = 0;
    int status = call(NULL, &outputLength);
    if (status == MACWLT_SUCCESS) {
        reply([NSData data], nil);
        return;
    }

    macwlt_err_t error = macwlt_last_error(_wallet);
    if (error != MACWLT_ERR_BUFFER_TOO_SMALL) {
        reply(nil, signingServiceError(error));
        return;
    }

    NSMutableData *output = [NSMutableData dataWithLength:outputLength];
    status = call(output.mutableBytes, &outputLength);
    if (status != MACWLT_SUCCESS) {
        reply(nil, [self lastError]);
        return;
    }

    output.length = outputLength;
    reply(output, nil);
}

@end
