/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "macwlt.h"

#import "Address.h"
#import "SEKeyManager.h"
#import "WalletSigner.h"
#import "WalletShareEnvelope.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>
#include <string.h>

struct macwlt_wallet {
    macwlt_err_t last_error;
    char *last_error_message;
    void *signing_engine;
};

static const size_t kCompressedSecp256k1PublicKeyLength = 33;

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
    NSString *description = error.localizedDescription;
    if (description.length > 0) return description;
    return [NSString stringWithFormat:@"%@ (%ld)", error.domain, (long)error.code];
}

static int failWith(macwlt_wallet_t *wallet, macwlt_err_t error) {
    if (wallet) {
        wallet->last_error = error;
        setLastErrorMessage(wallet, defaultMessageForError(error));
    }
    return MACWLT_FAILURE;
}

static int failWithMessage(macwlt_wallet_t *wallet,
                           macwlt_err_t error,
                           NSString *message) {
    if (wallet) {
        wallet->last_error = error;
        setLastErrorMessage(wallet, message.UTF8String ?: defaultMessageForError(error));
    }
    return MACWLT_FAILURE;
}

static int succeed(macwlt_wallet_t *wallet) {
    if (wallet) {
        wallet->last_error = MACWLT_OK;
        setLastErrorMessage(wallet, defaultMessageForError(MACWLT_OK));
    }
    return MACWLT_SUCCESS;
}

static void storeSigningEngine(macwlt_wallet_t *wallet, id<WalletSigningEngine> signingEngine) {
    if (wallet->signing_engine) (void)CFBridgingRelease(wallet->signing_engine);
    wallet->signing_engine = (__bridge_retained void *)signingEngine;
}

static id<WalletSigningEngine> currentSigningEngine(macwlt_wallet_t *wallet) {
    return wallet && wallet->signing_engine
        ? (__bridge id<WalletSigningEngine>)wallet->signing_engine
        : nil;
}

static void clearSigningEngine(macwlt_wallet_t *wallet) {
    if (!wallet || !wallet->signing_engine) return;
    (void)CFBridgingRelease(wallet->signing_engine);
    wallet->signing_engine = NULL;
}

static BOOL derivationPathStartsAtRoot(const char *derivation_path) {
    return (derivation_path && strcmp(derivation_path, "m") == 0) ||
        (derivation_path && strncmp(derivation_path, "m/", 2) == 0);
}

static BOOL derivationPathContainsHardenedComponent(const char *derivation_path) {
    if (!derivation_path) return NO;
    const char *componentStart = derivation_path;
    for (const char *p = derivation_path; ; p++) {
        if (*p == '/' || *p == '\0') {
            if (p > componentStart) {
                char last = *(p - 1);
                if (last == '\'' || last == 'h' || last == 'H') return YES;
            }
            if (*p == '\0') return NO;
            componentStart = p + 1;
        }
    }
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

static int copyData(macwlt_wallet_t *wallet,
                    NSData *data,
                    uint8_t *out_data,
                    size_t *inout_data_len) {
    if (*inout_data_len < data.length) {
        *inout_data_len = data.length;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!out_data) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    memcpy(out_data, data.bytes, data.length);
    *inout_data_len = data.length;
    return succeed(wallet);
}

static BOOL addressTypeIsSupported(macwlt_address_type_t address_type) {
    switch (address_type) {
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET:
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_TESTNET:
        case MACWLT_ADDRESS_ETHEREUM:
            return YES;
    }
    return NO;
}

static NSString *addressForPublicKey(NSData *publicKey,
                                     macwlt_address_type_t address_type) {
    switch (address_type) {
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET:
            return p2wpkhAddress(publicKey, YES);
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_TESTNET:
            return p2wpkhAddress(publicKey, NO);
        case MACWLT_ADDRESS_ETHEREUM:
            return ethereumAddress(publicKey);
    }
    NSCAssert(NO, @"Unhandled C wallet address type");
    return nil;
}

static int copyAddressString(macwlt_wallet_t *wallet,
                             NSString *address,
                             char *out_address,
                             size_t *inout_address_len) {
    const char *utf8 = address.UTF8String;
    if (!utf8) return failWith(wallet, MACWLT_ERR_INTERNAL);

    size_t requiredLength = strlen(utf8) + 1;
    if (*inout_address_len < requiredLength) {
        *inout_address_len = requiredLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!out_address) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    memcpy(out_address, utf8, requiredLength);
    *inout_address_len = requiredLength;
    return succeed(wallet);
}

int macwlt_wallet_create(macwlt_wallet_t **out_wallet) {
    if (!out_wallet) return MACWLT_FAILURE;
    *out_wallet = NULL;

    macwlt_wallet_t *wallet = calloc(1, sizeof(*wallet));
    if (!wallet) return MACWLT_FAILURE;

    WalletSigner *signingEngine = [[WalletSigner alloc] init];
    if (!signingEngine) {
        free(wallet);
        return MACWLT_FAILURE;
    }

    wallet->last_error = MACWLT_OK;
    setLastErrorMessage(wallet, defaultMessageForError(MACWLT_OK));
    wallet->signing_engine = (__bridge_retained void *)signingEngine;
    *out_wallet = wallet;
    return MACWLT_SUCCESS;
}

void macwlt_wallet_free(macwlt_wallet_t *wallet) {
    if (!wallet) return;
    clearSigningEngine(wallet);
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
        WalletSigner *signingEngine = [[WalletSigner alloc] init];
        if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);
        storeSigningEngine(wallet, signingEngine);

        NSError *error = nil;
        NSURL *storageURL = [WalletShareEnvelope defaultStorageURL];
        if ([[NSFileManager defaultManager] fileExistsAtPath:storageURL.path] &&
            ![[NSFileManager defaultManager] removeItemAtURL:storageURL error:&error]) {
            return failWithMessage(wallet,
                                   MACWLT_ERR_UNAVAILABLE,
                                   messageForNSError(error));
        }

        if (![SEKeyManager deleteAllManagedKeysWithError:&error]) {
            return failWithMessage(wallet,
                                   MACWLT_ERR_UNAVAILABLE,
                                   messageForNSError(error));
        }
        return succeed(wallet);
    }
}

int macwlt_bootstrap_wallet(macwlt_wallet_t *wallet,
                            uint8_t *out_joint_pubkey,
                            size_t *inout_joint_pubkey_len) {
    if (!wallet || !inout_joint_pubkey_len) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }

    if (*inout_joint_pubkey_len < kCompressedSecp256k1PublicKeyLength) {
        *inout_joint_pubkey_len = kCompressedSecp256k1PublicKeyLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!out_joint_pubkey) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    @autoreleasepool {
        NSError *error = nil;
        id<WalletSigningEngine> signingEngine = currentSigningEngine(wallet);
        if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);

        NSData *jointPublicKey = [signingEngine bootstrapWithError:&error];
        if (!jointPublicKey) {
            macwlt_err_t walletError = [error.domain isEqualToString:WalletSignerErrorDomain]
                ? errorForSignerError(error)
                : MACWLT_ERR_UNAVAILABLE;
            return failWithMessage(wallet,
                                   walletError,
                                   messageForNSError(error));
        }

        if (jointPublicKey.length != kCompressedSecp256k1PublicKeyLength) {
            return failWith(wallet, MACWLT_ERR_INTERNAL);
        }

        memcpy(out_joint_pubkey, jointPublicKey.bytes, jointPublicKey.length);
        *inout_joint_pubkey_len = jointPublicKey.length;
        return succeed(wallet);
    }
}

int macwlt_sign_psbt(macwlt_wallet_t *wallet,
                     const uint8_t *psbt,
                     size_t psbt_len,
                     uint8_t *out_signed_psbt,
                     size_t *inout_signed_psbt_len) {
    if (!wallet || !psbt || psbt_len == 0 || !inout_signed_psbt_len) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    id<WalletSigningEngine> signingEngine = currentSigningEngine(wallet);
    if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);

    @autoreleasepool {
        NSError *error = nil;
        NSData *signedPSBT =
            [signingEngine signedPSBTForData:[NSData dataWithBytes:psbt length:psbt_len]
                                        error:&error];
        if (!signedPSBT) {
            return failWithMessage(wallet,
                                   errorForSignerError(error),
                                   messageForNSError(error));
        }
        return copyData(wallet, signedPSBT, out_signed_psbt, inout_signed_psbt_len);
    }
}

int macwlt_sign_eth_tx(macwlt_wallet_t *wallet,
                       const uint8_t *transaction,
                       size_t transaction_len,
                       uint8_t *out_signature,
                       size_t *inout_signature_len) {
    if (!wallet || !transaction || transaction_len == 0 || !inout_signature_len) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    id<WalletSigningEngine> signingEngine = currentSigningEngine(wallet);
    if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);

    @autoreleasepool {
        NSError *error = nil;
        NSData *signature =
            [signingEngine ethereumSignatureForTransaction:[NSData dataWithBytes:transaction
                                                                          length:transaction_len]
                                                     error:&error];
        if (!signature) {
            return failWithMessage(wallet,
                                   errorForSignerError(error),
                                   messageForNSError(error));
        }
        return copyData(wallet, signature, out_signature, inout_signature_len);
    }
}

int macwlt_export_pubkey(macwlt_wallet_t *wallet,
                         const char *derivation_path,
                         uint8_t *out_pubkey,
                         size_t *inout_pubkey_len) {
    if (!wallet || !derivation_path || !inout_pubkey_len) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (!derivationPathStartsAtRoot(derivation_path)) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (derivationPathContainsHardenedComponent(derivation_path)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }

    if (*inout_pubkey_len < kCompressedSecp256k1PublicKeyLength) {
        *inout_pubkey_len = kCompressedSecp256k1PublicKeyLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!out_pubkey) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    id<WalletSigningEngine> signingEngine = currentSigningEngine(wallet);
    if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);

    NSString *path = [NSString stringWithUTF8String:derivation_path];
    if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    NSError *error = nil;
    NSData *publicKey = [signingEngine publicKeyForDerivationPath:path error:&error];
    if (!publicKey) {
        return failWithMessage(wallet,
                               errorForSignerError(error),
                               messageForNSError(error));
    }

    if (publicKey.length != kCompressedSecp256k1PublicKeyLength) {
        return failWith(wallet, MACWLT_ERR_INTERNAL);
    }

    memcpy(out_pubkey, publicKey.bytes, publicKey.length);
    *inout_pubkey_len = publicKey.length;
    return succeed(wallet);
}

int macwlt_export_address(macwlt_wallet_t *wallet,
                          const char *derivation_path,
                          macwlt_address_type_t address_type,
                          char *out_address,
                          size_t *inout_address_len) {
    if (!wallet || !derivation_path || !inout_address_len) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (!addressTypeIsSupported(address_type)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }
    if (!derivationPathStartsAtRoot(derivation_path)) {
        return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);
    }
    if (derivationPathContainsHardenedComponent(derivation_path)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }

    id<WalletSigningEngine> signingEngine = currentSigningEngine(wallet);
    if (!signingEngine) return failWith(wallet, MACWLT_ERR_INTERNAL);

    NSString *path = [NSString stringWithUTF8String:derivation_path];
    if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    NSError *error = nil;
    NSData *publicKey = [signingEngine publicKeyForDerivationPath:path error:&error];
    if (!publicKey) {
        return failWithMessage(wallet,
                               errorForSignerError(error),
                               messageForNSError(error));
    }

    NSString *address = addressForPublicKey(publicKey, address_type);

    if (!address) return failWith(wallet, MACWLT_ERR_INTERNAL);
    return copyAddressString(wallet, address, out_address, inout_address_len);
}

int macwlt_export_attestation(macwlt_wallet_t *wallet,
                              const uint8_t *challenge,
                              size_t challenge_len,
                              uint8_t *out_attestation,
                              size_t *inout_attestation_len) {
    (void)challenge;
    (void)challenge_len;
    (void)out_attestation;
    (void)inout_attestation_len;
    return failWith(wallet, wallet ? MACWLT_ERR_UNSUPPORTED : MACWLT_ERR_INVALID_ARGUMENT);
}
