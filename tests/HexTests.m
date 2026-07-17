/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/hex.h"

@interface HexTests : MacwltTestCase
@end

@implementation HexTests

- (void)testLowercaseEncodingPreservesLeadingZeroes {
    const uint8_t bytes[] = {0x00, 0xab, 0xff};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];

    NSString *encoded = hex(data);

    XCTAssertEqualObjects(encoded, @"00abff");
}

@end
