/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "macwlt.h"

#import "SigningServiceClient.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>
#include <string.h>

struct macwlt_wallet {
    macwlt_err_t last_error;
    char *last_error_message;
    void *service_client;
};

static const size_t kCompressedSecp256k1PublicKeyLength = 33;
static NSString * const kSigningServiceErrorDomain = @"macwlt.SigningService";

static const char *defaultMessageForError(macwlt_err_t error) {
    switch (error) {
        case MACWLT_OK:
            return "ok";
        case MACWLT_ERR_INVALID_ARGUMENT:
            return "invalid argument";
        case MACWLT_ERR_UNAVAILABLE:
            return "wallet data is unavailable";
        case MACWLT_ERR_AUTH_REQUIRED:
            return "authentication is required";
        case MACWLT_ERR_AUTH_FAILED:
            return "authentication failed";
        case MACWLT_ERR_BUFFER_TOO_SMALL:
            return "output buffer is too small";
        case MACWLT_ERR_UNSUPPORTED:
            return "operation is unsupported";
        case MACWLT_ERR_PARSE_FAILED:
            return "input parsing failed";
        case MACWLT_ERR_SIGNING_FAILED:
            return "signing failed";
        case MACWLT_ERR_INTERNAL:
            return "internal native error";
    }
    NSCAssert(NO, @"Unhandled macwlt error code");
    return "unknown native error";
}

static void setLastErrorMessage(macwlt_wallet_t *wallet, const char *message) {
    if (!wallet) return;
    free(wallet->last_error_message);
    wallet->last_error_message = message ? strdup(message) : NULL;
}

static NSString *messageForNSError(NSError *error) {
    if (!error) return nil;
    return error.localizedDescription.length > 0
        ? error.localizedDescription
        : [NSString stringWithFormat:@"%@ (%ld)", error.domain, (long)error.code];
}

static int failWith(macwlt_wallet_t *wallet, macwlt_err_t error) {
    if (wallet) {
        wallet->last_error = error;
        setLastErrorMessage(wallet, defaultMessageForError(error));
    }
    return MACWLT_FAILURE;
}

static int failWithNSError(macwlt_wallet_t *wallet, NSError *error) {
    macwlt_err_t code = MACWLT_ERR_UNAVAILABLE;
    if ([error.domain isEqualToString:kSigningServiceErrorDomain] &&
        error.code >= MACWLT_ERR_INVALID_ARGUMENT &&
        error.code <= MACWLT_ERR_INTERNAL) {
        code = (macwlt_err_t)error.code;
    }
    if (wallet) {
        wallet->last_error = code;
        setLastErrorMessage(wallet,
                            messageForNSError(error).UTF8String ?:
                            defaultMessageForError(code));
    }
    return MACWLT_FAILURE;
}

static int succeed(macwlt_wallet_t *wallet) {
    wallet->last_error = MACWLT_OK;
    setLastErrorMessage(wallet, defaultMessageForError(MACWLT_OK));
    return MACWLT_SUCCESS;
}

static SigningServiceClient *serviceClient(macwlt_wallet_t *wallet) {
    return wallet && wallet->service_client
        ? (__bridge SigningServiceClient *)wallet->service_client
        : nil;
}

static BOOL derivationPathStartsAtRoot(const char *derivationPath) {
    return derivationPath &&
        (strcmp(derivationPath, "m") == 0 ||
         strncmp(derivationPath, "m/", 2) == 0);
}

static BOOL derivationPathContainsHardenedComponent(const char *derivationPath) {
    if (!derivationPath) return NO;
    const char *componentStart = derivationPath;
    for (const char *cursor = derivationPath; ; cursor++) {
        if (*cursor == '/' || *cursor == '\0') {
            if (cursor > componentStart) {
                char last = *(cursor - 1);
                if (last == '\'' || last == 'h' || last == 'H') return YES;
            }
            if (*cursor == '\0') return NO;
            componentStart = cursor + 1;
        }
    }
}

static BOOL addressTypeIsSupported(macwlt_address_type_t addressType) {
    switch (addressType) {
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET:
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_TESTNET:
        case MACWLT_ADDRESS_ETHEREUM:
        case MACWLT_ADDRESS_BITCOIN_P2TR_MAINNET:
        case MACWLT_ADDRESS_BITCOIN_P2TR_TESTNET:
            return YES;
    }
    return NO;
}

static int copyData(macwlt_wallet_t *wallet,
                    NSData *data,
                    uint8_t *output,
                    size_t *inoutLength) {
    if (*inoutLength < data.length) {
        *inoutLength = data.length;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!output) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    memcpy(output, data.bytes, data.length);
    *inoutLength = data.length;
    return succeed(wallet);
}

static int copyString(macwlt_wallet_t *wallet,
                      NSString *string,
                      char *output,
                      size_t *inoutLength) {
    const char *utf8 = string.UTF8String;
    if (!utf8) return failWith(wallet, MACWLT_ERR_INTERNAL);
    size_t requiredLength = strlen(utf8) + 1;
    if (*inoutLength < requiredLength) {
        *inoutLength = requiredLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!output) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    memcpy(output, utf8, requiredLength);
    *inoutLength = requiredLength;
    return succeed(wallet);
}

int macwlt_wallet_create(macwlt_wallet_t **outWallet) {
    if (!outWallet) return MACWLT_FAILURE;
    *outWallet = NULL;

    macwlt_wallet_t *wallet = calloc(1, sizeof(*wallet));
    if (!wallet) return MACWLT_FAILURE;
    SigningServiceClient *client = [SigningServiceClient clientWithDefaultService];
    if (!client) {
        free(wallet);
        return MACWLT_FAILURE;
    }
    wallet->service_client = (__bridge_retained void *)client;
    wallet->last_error = MACWLT_OK;
    setLastErrorMessage(wallet, defaultMessageForError(MACWLT_OK));
    *outWallet = wallet;
    return MACWLT_SUCCESS;
}

void macwlt_wallet_free(macwlt_wallet_t *wallet) {
    if (!wallet) return;
    SigningServiceClient *client = serviceClient(wallet);
    [client invalidate];
    if (wallet->service_client) {
        (void)CFBridgingRelease(wallet->service_client);
    }
    free(wallet->last_error_message);
    free(wallet);
}

macwlt_err_t macwlt_last_error(macwlt_wallet_t *wallet) {
    return wallet ? wallet->last_error : MACWLT_ERR_INVALID_ARGUMENT;
}

const char *macwlt_last_error_message(macwlt_wallet_t *wallet) {
    if (!wallet) return defaultMessageForError(MACWLT_ERR_INVALID_ARGUMENT);
    return wallet->last_error_message ?: defaultMessageForError(wallet->last_error);
}

int macwlt_reset_wallet(macwlt_wallet_t *wallet) {
    if (!wallet) return MACWLT_FAILURE;
    @autoreleasepool {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block BOOL reset = NO;
        __block NSError *operationError = nil;
        [serviceClient(wallet) resetWalletWithReply:^(BOOL didReset, NSError *error) {
            reset = didReset;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return reset ? succeed(wallet) : failWithNSError(wallet, operationError);
    }
}

int macwlt_bootstrap_wallet(macwlt_wallet_t *wallet,
                            uint8_t *outJointPublicKey,
                            size_t *inoutJointPublicKeyLength) {
    if (!wallet || !inoutJointPublicKeyLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (*inoutJointPublicKeyLength < kCompressedSecp256k1PublicKeyLength) {
        *inoutJointPublicKeyLength = kCompressedSecp256k1PublicKeyLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!outJointPublicKey) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    @autoreleasepool {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *publicKey = nil;
        __block NSError *operationError = nil;
        [serviceClient(wallet) bootstrapWalletWithReply:^(NSData *value, NSError *error) {
            publicKey = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        if (!publicKey) return failWithNSError(wallet, operationError);
        if (publicKey.length != kCompressedSecp256k1PublicKeyLength) {
            return failWith(wallet, MACWLT_ERR_INTERNAL);
        }
        return copyData(wallet, publicKey, outJointPublicKey,
                        inoutJointPublicKeyLength);
    }
}

int macwlt_sign_psbt(macwlt_wallet_t *wallet,
                     const uint8_t *psbt,
                     size_t psbtLength,
                     uint8_t *outSignedPSBT,
                     size_t *inoutSignedPSBTLength) {
    if (!wallet || !psbt || psbtLength == 0 || !inoutSignedPSBTLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    @autoreleasepool {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *signedPSBT = nil;
        __block NSError *operationError = nil;
        NSData *input = [NSData dataWithBytes:psbt length:psbtLength];
        [serviceClient(wallet) signPSBT:input withReply:^(NSData *value, NSError *error) {
            signedPSBT = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return signedPSBT
            ? copyData(wallet, signedPSBT, outSignedPSBT, inoutSignedPSBTLength)
            : failWithNSError(wallet, operationError);
    }
}

int macwlt_sign_eth_tx(macwlt_wallet_t *wallet,
                       const uint8_t *transaction,
                       size_t transactionLength,
                       uint8_t *outSignature,
                       size_t *inoutSignatureLength) {
    if (!wallet || !transaction || transactionLength == 0 || !inoutSignatureLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    @autoreleasepool {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *signature = nil;
        __block NSError *operationError = nil;
        NSData *input = [NSData dataWithBytes:transaction length:transactionLength];
        [serviceClient(wallet) signEthTx:input withReply:^(NSData *value, NSError *error) {
            signature = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return signature
            ? copyData(wallet, signature, outSignature, inoutSignatureLength)
            : failWithNSError(wallet, operationError);
    }
}

int macwlt_export_pubkey(macwlt_wallet_t *wallet,
                         const char *derivationPath,
                         uint8_t *outPublicKey,
                         size_t *inoutPublicKeyLength) {
    if (!wallet || !derivationPath || !inoutPublicKeyLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (!derivationPathStartsAtRoot(derivationPath)) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (derivationPathContainsHardenedComponent(derivationPath)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }
    if (*inoutPublicKeyLength < kCompressedSecp256k1PublicKeyLength) {
        *inoutPublicKeyLength = kCompressedSecp256k1PublicKeyLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!outPublicKey) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    @autoreleasepool {
        NSString *path = [NSString stringWithUTF8String:derivationPath];
        if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *publicKey = nil;
        __block NSError *operationError = nil;
        [serviceClient(wallet)
            exportPubkeyForDerivationPath:path
                                withReply:^(NSData *value, NSError *error) {
            publicKey = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        if (!publicKey) return failWithNSError(wallet, operationError);
        if (publicKey.length != kCompressedSecp256k1PublicKeyLength) {
            return failWith(wallet, MACWLT_ERR_INTERNAL);
        }
        return copyData(wallet, publicKey, outPublicKey, inoutPublicKeyLength);
    }
}

int macwlt_export_address(macwlt_wallet_t *wallet,
                          const char *derivationPath,
                          macwlt_address_type_t addressType,
                          char *outAddress,
                          size_t *inoutAddressLength) {
    if (!wallet || !derivationPath || !inoutAddressLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (!addressTypeIsSupported(addressType)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }
    if (!derivationPathStartsAtRoot(derivationPath)) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (derivationPathContainsHardenedComponent(derivationPath)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }

    @autoreleasepool {
        NSString *path = [NSString stringWithUTF8String:derivationPath];
        if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSString *address = nil;
        __block NSError *operationError = nil;
        [serviceClient(wallet)
            exportAddressForDerivationPath:path
                                addressType:(SigningServiceAddressType)addressType
                                  withReply:^(NSString *value, NSError *error) {
            address = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return address
            ? copyString(wallet, address, outAddress, inoutAddressLength)
            : failWithNSError(wallet, operationError);
    }
}

int macwlt_export_attestation(macwlt_wallet_t *wallet,
                              const uint8_t *challenge,
                              size_t challengeLength,
                              uint8_t *outAttestation,
                              size_t *inoutAttestationLength) {
    if (!wallet || !challenge || challengeLength == 0 || !inoutAttestationLength) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    @autoreleasepool {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        __block NSData *attestation = nil;
        __block NSError *operationError = nil;
        NSData *input = [NSData dataWithBytes:challenge length:challengeLength];
        [serviceClient(wallet)
            exportAttestationForChallenge:input
                                withReply:^(NSData *value, NSError *error) {
            attestation = value;
            operationError = error;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return attestation
            ? copyData(wallet, attestation, outAttestation, inoutAttestationLength)
            : failWithNSError(wallet, operationError);
    }
}
