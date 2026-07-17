/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/PSBT.h"

@interface PSBTTests : MacwltTestCase
@end

@implementation PSBTTests

- (void)testInvalidDataReturnsError {
    NSError *error = nil;

    PSBT *psbt = [PSBT psbtWithData:[@"not a psbt" dataUsingEncoding:NSUTF8StringEncoding]
                              error:&error];

    XCTAssertNil(psbt);
    XCTAssertNotNil(error);
}

@end
