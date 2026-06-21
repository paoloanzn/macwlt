/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "hex.h"

// Returns hex representation as a string of N bytes.
NSString *hex(NSData *d) {
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    const uint8_t *b = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}
