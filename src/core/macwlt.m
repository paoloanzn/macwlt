/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "macwlt.h"

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
    if (!derivationPathIsRoot(derivation_path)) {
        return failWith(wallet, MACWLT_ERR_UNSUPPORTED);
    }

    if (*inout_pubkey_len < kCompressedSecp256k1PublicKeyLength) {
        *inout_pubkey_len = kCompressedSecp256k1PublicKeyLength;
        return failWith(wallet, MACWLT_ERR_BUFFER_TOO_SMALL);
    }
    if (!out_pubkey) return failWith(wallet, MACWLT_ERR_INVALID_ARGUMENT);

    WalletShareEnvelope *shareEnvelope = currentShareEnvelope(wallet);
    if (!shareEnvelope) return failWith(wallet, MACWLT_ERR_UNAVAILABLE);

    NSData *jointPublicKey = shareEnvelope.jointCompressedPublicKey;
    if (jointPublicKey.length != kCompressedSecp256k1PublicKeyLength) {
        return failWith(wallet, MACWLT_ERR_INTERNAL);
    }

    memcpy(out_pubkey, jointPublicKey.bytes, jointPublicKey.length);
    *inout_pubkey_len = jointPublicKey.length;
    return succeed(wallet);
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
