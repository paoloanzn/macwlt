/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include "RIPEMD160.h"

// RIPEMD-160 comes from OpenSSL's libcrypto. The one-shot RIPEMD160() routine
// (see the RIPEMD160_Final(3ssl) man page) is deprecated as a public API in
// OpenSSL 3.0 but remains the simplest way to reach the digest; suppress the
// deprecation notice rather than reimplement the algorithm in-tree.
#define OPENSSL_SUPPRESS_DEPRECATED
#include <openssl/ripemd.h>

void ripemd160(const uint8_t *data, size_t len,
               uint8_t out[RIPEMD160_DIGEST_LENGTH]) {
    RIPEMD160(data, len, out);
}
