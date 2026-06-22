/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_BECH32_H
#define MACWLT_BECH32_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BECH32_MAX_LEN 90

// Writes a NUL-terminated SegWit address into `out`; returns false for invalid arguments.
bool segwitAddrEncode(char *out, const char *hrp,
                      int witver, const uint8_t *program, size_t programLen);

#endif /* MACWLT_BECH32_H */
