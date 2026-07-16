/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_H
#define MACWLT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct macwlt_wallet macwlt_wallet_t;

typedef enum macwlt_err {
    MACWLT_OK = 0,
    MACWLT_ERR_INVALID_ARGUMENT = 1,
    MACWLT_ERR_UNAVAILABLE = 2,
    MACWLT_ERR_AUTH_REQUIRED = 3,
    MACWLT_ERR_AUTH_FAILED = 4,
    MACWLT_ERR_BUFFER_TOO_SMALL = 5,
    MACWLT_ERR_UNSUPPORTED = 6,
    MACWLT_ERR_PARSE_FAILED = 7,
    MACWLT_ERR_SIGNING_FAILED = 8,
    MACWLT_ERR_INTERNAL = 9,
} macwlt_err_t;

#define MACWLT_SUCCESS 0
#define MACWLT_FAILURE (-1)

int macwlt_wallet_create(macwlt_wallet_t **out_wallet);
void macwlt_wallet_free(macwlt_wallet_t *wallet);

macwlt_err_t macwlt_last_error(macwlt_wallet_t *wallet);

int macwlt_bootstrap_wallet(macwlt_wallet_t *wallet,
                            uint8_t *out_joint_pubkey,
                            size_t *inout_joint_pubkey_len);

int macwlt_sign_psbt(macwlt_wallet_t *wallet,
                     const uint8_t *psbt,
                     size_t psbt_len,
                     uint8_t *out_signed_psbt,
                     size_t *inout_signed_psbt_len);

int macwlt_sign_eth_tx(macwlt_wallet_t *wallet,
                       const uint8_t *transaction,
                       size_t transaction_len,
                       uint8_t *out_signature,
                       size_t *inout_signature_len);

int macwlt_export_pubkey(macwlt_wallet_t *wallet,
                         const char *derivation_path,
                         uint8_t *out_pubkey,
                         size_t *inout_pubkey_len);

int macwlt_export_attestation(macwlt_wallet_t *wallet,
                              const uint8_t *challenge,
                              size_t challenge_len,
                              uint8_t *out_attestation,
                              size_t *inout_attestation_len);

#ifdef __cplusplus
}
#endif

#endif /* MACWLT_H */
