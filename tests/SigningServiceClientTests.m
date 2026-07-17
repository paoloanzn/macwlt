/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/SigningServiceClient.h"

@interface SigningServiceClientTests : MacwltTestCase
@property (nonatomic, strong) SigningServiceClient *sut;
@end

@implementation SigningServiceClientTests

- (void)tearDown {
    [self.sut invalidate];
    self.sut = nil;
    [super tearDown];
}

- (void)testDefaultClientUsesSigningServiceBundleIdentifier {
    self.sut = [SigningServiceClient clientWithDefaultService];

    XCTAssertEqualObjects(SigningServiceClientDefaultServiceName,
                          @"com.macwlt.SigningService");
    XCTAssertEqualObjects(self.sut.serviceName, SigningServiceClientDefaultServiceName);
}

@end
