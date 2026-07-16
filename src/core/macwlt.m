/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "macwlt.h"

#import "Address.h"
#import "WalletAddressDerivation.h"
#import "WalletPublicKeyDerivation.h"
#import "WalletShareEnvelope.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>
#include <string.h>

struct macwlt_wallet {
    macwlt_err_t last_error;
    void *share_envelope;
};

static const size_t kCompressedSecp256k1PublicKeyLength = 33;

static int failWith(macwlt_wallet_t *wallet, macwlt_err_t error) {
    if (wallet) wallet->last_error = error;
    return MACWLT_FAILURE;
}

static int succeed(macwlt_wallet_t *wallet) {
    if (wallet) wallet->last_error = MACWLT_OK;
    return MACWLT_SUCCESS;
}

static void storeShareEnvelope(macwlt_wallet_t *wallet, WalletShareEnvelope *shareEnvelope) {
    if (wallet->share_envelope) (void)CFBridgingRelease(wallet->share_envelope);
    wallet->share_envelope = (__bridge_retained void *)shareEnvelope;
}

static WalletShareEnvelope *currentShareEnvelope(macwlt_wallet_t *wallet) {
    return wallet && wallet->share_envelope
        ? (__bridge WalletShareEnvelope *)wallet->share_envelope
        : nil;
}

static BOOL derivationPathIsRoot(const char *derivation_path) {
    return derivation_path && strcmp(derivation_path, "m") == 0;
}

static BOOL derivationPathStartsAtRoot(const char *derivation_path) {
    return derivationPathIsRoot(derivation_path) ||
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

static macwlt_err_t errorForPublicDerivationError(NSError *error) {
    if (![error.domain isEqualToString:WalletPublicKeyDerivationErrorDomain]) {
        return MACWLT_ERR_INTERNAL;
    }

    switch (error.code) {
        case WalletPublicKeyDerivationErrorInvalidRootPublicKey:
        case WalletPublicKeyDerivationErrorInvalidChainCode:
        case WalletPublicKeyDerivationErrorInvalidPath:
            return MACWLT_ERR_INVALID_ARGUMENT;
        case WalletPublicKeyDerivationErrorUnsupportedHardenedPath:
            return MACWLT_ERR_UNSUPPORTED;
        case WalletPublicKeyDerivationErrorDerivationFailed:
        case WalletPublicKeyDerivationErrorRandomFailed:
            return MACWLT_ERR_INTERNAL;
    }
    NSCAssert(NO, @"Unhandled public derivation error code");
    return MACWLT_ERR_INTERNAL;
}

static macwlt_err_t errorForAddressDerivationError(NSError *error) {
    if ([error.domain isEqualToString:WalletPublicKeyDerivationErrorDomain]) {
        return errorForPublicDerivationError(error);
    }
    if (![error.domain isEqualToString:WalletAddressDerivationErrorDomain]) {
        return MACWLT_ERR_INTERNAL;
    }

    switch (error.code) {
        case WalletAddressDerivationErrorUnsupportedAddressType:
            return MACWLT_ERR_UNSUPPORTED;
        case WalletAddressDerivationErrorAddressEncodingFailed:
            return MACWLT_ERR_INTERNAL;
    }
    NSCAssert(NO, @"Unhandled address derivation error code");
    return MACWLT_ERR_INTERNAL;
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

static WalletAddressType walletAddressType(macwlt_address_type_t address_type) {
    switch (address_type) {
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET:
            return WalletAddressTypeBitcoinP2WPKHMainnet;
        case MACWLT_ADDRESS_BITCOIN_P2WPKH_TESTNET:
            return WalletAddressTypeBitcoinP2WPKHTestnet;
        case MACWLT_ADDRESS_ETHEREUM:
            return WalletAddressTypeEthereum;
    }
    NSCAssert(NO, @"Unhandled C wallet address type");
    return WalletAddressTypeBitcoinP2WPKHMainnet;
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

    wallet->last_error = MACWLT_OK;
    *out_wallet = wallet;
    return MACWLT_SUCCESS;
}

void macwlt_wallet_free(macwlt_wallet_t *wallet) {
    if (!wallet) return;
    if (wallet->share_envelope) (void)CFBridgingRelease(wallet->share_envelope);
    free(wallet);
}

macwlt_err_t macwlt_last_error(macwlt_wallet_t *wallet) {
    return wallet ? wallet->last_error : MACWLT_ERR_INVALID_ARGUMENT;
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
        WalletShareEnvelope *shareEnvelope =
            [WalletShareEnvelope loadOrBootstrapFromDefaultStorageWithError:&error];
        if (!shareEnvelope) {
            (void)error;
            return failWith(wallet, MACWLT_ERR_UNAVAILABLE);
        }

        NSData *jointPublicKey = shareEnvelope.jointCompressedPublicKey;
        if (jointPublicKey.length != kCompressedSecp256k1PublicKeyLength) {
            return failWith(wallet, MACWLT_ERR_INTERNAL);
        }

        memcpy(out_joint_pubkey, jointPublicKey.bytes, jointPublicKey.length);
        *inout_joint_pubkey_len = jointPublicKey.length;
        storeShareEnvelope(wallet, shareEnvelope);
        return succeed(wallet);
    }
}

int macwlt_sign_psbt(macwlt_wallet_t *wallet,
                     const uint8_t *psbt,
                     size_t psbt_len,
                     uint8_t *out_signed_psbt,
                     size_t *inout_signed_psbt_len) {
    (void)psbt;
    (void)psbt_len;
    (void)out_signed_psbt;
    (void)inout_signed_psbt_len;
    return failWith(wallet, wallet ? MACWLT_ERR_UNSUPPORTED : MACWLT_ERR_INVALID_ARGUMENT);
}

int macwlt_sign_eth_tx(macwlt_wallet_t *wallet,
                       const uint8_t *transaction,
                       size_t transaction_len,
                       uint8_t *out_signature,
                       size_t *inout_signature_len) {
    (void)transaction;
    (void)transaction_len;
    (void)out_signature;
    (void)inout_signature_len;
    return failWith(wallet, wallet ? MACWLT_ERR_UNSUPPORTED : MACWLT_ERR_INVALID_ARGUMENT);
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

    WalletShareEnvelope *shareEnvelope = currentShareEnvelope(wallet);
    if (!shareEnvelope) return failWith(wallet, MACWLT_ERR_UNAVAILABLE);

    NSData *publicKey = nil;
    if (derivationPathIsRoot(derivation_path)) {
        publicKey = shareEnvelope.jointCompressedPublicKey;
    } else {
        NSData *chainCode = shareEnvelope.chainCode;
        if (!chainCode) return failWith(wallet, MACWLT_ERR_UNAVAILABLE);

        NSString *path = [NSString stringWithUTF8String:derivation_path];
        if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

        NSError *error = nil;
        publicKey = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:shareEnvelope.jointCompressedPublicKey
                                                                         chainCode:chainCode
                                                                    derivationPath:path
                                                                             error:&error];
        if (!publicKey) return failWith(wallet, errorForPublicDerivationError(error));
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

    WalletShareEnvelope *shareEnvelope = currentShareEnvelope(wallet);
    if (!shareEnvelope) return failWith(wallet, MACWLT_ERR_UNAVAILABLE);

    NSString *address = nil;
    if (derivationPathIsRoot(derivation_path)) {
        address = addressForPublicKey(shareEnvelope.jointCompressedPublicKey, address_type);
    } else {
        NSData *chainCode = shareEnvelope.chainCode;
        if (!chainCode) return failWith(wallet, MACWLT_ERR_UNAVAILABLE);

        NSString *path = [NSString stringWithUTF8String:derivation_path];
        if (!path) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

        NSError *error = nil;
        address = [WalletAddressDerivation addressForRootCompressedPublicKey:shareEnvelope.jointCompressedPublicKey
                                                                   chainCode:chainCode
                                                              derivationPath:path
                                                                 addressType:walletAddressType(address_type)
                                                                       error:&error];
        if (!address) return failWith(wallet, errorForAddressDerivationError(error));
    }

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
