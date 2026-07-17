/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

@interface BuildConfigurationTests : MacwltTestCase
@end

@implementation BuildConfigurationTests

- (void)testAssertionsAreEnabledInThisTarget {
#ifdef NS_BLOCK_ASSERTIONS
    XCTFail(@"NS_BLOCK_ASSERTIONS is set; every precondition test is a no-op");
#endif
}

@end
