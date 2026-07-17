/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef MACWLT_SECURE_WIPE_H
#define MACWLT_SECURE_WIPE_H

#include <stddef.h>
#include <stdint.h>

static inline void secureWipe(void *p, size_t n) {
    if (!p || n == 0) return;

    volatile uint8_t *bytes = (volatile uint8_t *)p;
    for (size_t i = 0; i < n; i++) {
        bytes[i] = 0;
    }
}

#endif /* MACWLT_SECURE_WIPE_H */
