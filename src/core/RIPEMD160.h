/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_RIPEMD160_H
#define MACWLT_RIPEMD160_H

#include <stddef.h>
#include <stdint.h>

#define RIPEMD160_DIGEST_LENGTH 20

void ripemd160(const uint8_t *data, size_t len,
               uint8_t out[RIPEMD160_DIGEST_LENGTH]);

#endif /* MACWLT_RIPEMD160_H */
