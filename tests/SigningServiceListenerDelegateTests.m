/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/SigningService.h"
#import "../src/core/SigningServiceListenerDelegate.h"

@interface MockXPCConnection : NSObject
@property (nonatomic, strong) NSXPCInterface *exportedInterface;
@property (nonatomic, strong) id exportedObject;
@property (nonatomic, readonly) BOOL resumed;
- (void)resume;
@end

@implementation MockXPCConnection {
    BOOL _resumed;
}

- (void)resume {
    _resumed = YES;
}

- (BOOL)resumed {
    return _resumed;
}

@end

@interface SigningServiceListenerDelegateTests : MacwltTestCase
@property (nonatomic, strong) SigningService *service;
@property (nonatomic, strong) SigningServiceListenerDelegate *sut;
@end

@implementation SigningServiceListenerDelegateTests

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.service = [[SigningService alloc] initWithError:&error];
    XCTAssertNotNil(self.service, @"SigningService init failed: %@", error);
    self.sut = [[SigningServiceListenerDelegate alloc] initWithService:self.service];
}

- (void)tearDown {
    self.sut = nil;
    self.service = nil;
    [super tearDown];
}

- (void)testAcceptedConnectionExportsServiceAndResumes {
    MockXPCConnection *connection = [MockXPCConnection new];
    NSObject *listener = [NSObject new];

    BOOL accepted = [self.sut listener:(NSXPCListener *)listener
             shouldAcceptNewConnection:(NSXPCConnection *)connection];

    XCTAssertTrue(accepted);
    XCTAssertNotNil(connection.exportedInterface);
    XCTAssertEqualObjects(connection.exportedObject, self.service);
    XCTAssertTrue(connection.resumed);
}

@end
