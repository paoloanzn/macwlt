/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <XCTest/XCTest.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface MacwltTestCase : XCTestCase
@end

NSData *MacwltTestDataFromHex(NSString *string);
NSData *MacwltTestScalarData(uint8_t value);
NSData *MacwltTestCompressedPublicKeyForSecret(NSData *secret);
NSData *MacwltTestPrivateKeyByMultiplying(NSData *a, NSData *b);
NSData *MacwltTestPrivateKeyByAdding(NSData *a, NSData *b);
NSURL *MacwltTestTemporaryFileURL(NSString *name);
BOOL MacwltTestReadTriggersProtectionFault(volatile uint8_t *address);
BOOL MacwltTestWalletResetTestsEnabled(void);

NS_ASSUME_NONNULL_END
