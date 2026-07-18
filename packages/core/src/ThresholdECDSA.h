/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_THRESHOLD_ECDSA_H
#define MACWLT_THRESHOLD_ECDSA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int macwlt_threshold_ecdsa_generate(uint8_t **out_share_a,
                                    size_t *out_share_a_len,
                                    uint8_t **out_share_b,
                                    size_t *out_share_b_len,
                                    uint8_t out_public_key_33[33],
                                    char *error_buffer,
                                    size_t error_capacity);

int macwlt_threshold_ecdsa_sign_transaction(const uint8_t *share_a,
                                            size_t share_a_len,
                                            const uint8_t *share_b,
                                            size_t share_b_len,
                                            const uint8_t *transaction,
                                            size_t transaction_len,
                                            uint8_t out_signature_64[64],
                                            char *error_buffer,
                                            size_t error_capacity);

void macwlt_threshold_ecdsa_free(uint8_t *bytes, size_t length);

#ifdef __cplusplus
}
#endif

#endif /* MACWLT_THRESHOLD_ECDSA_H */
