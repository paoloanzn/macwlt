/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningServiceListenerDelegate.h"

#import "SigningService.h"
#import "SigningServiceProtocol.h"

@implementation SigningServiceListenerDelegate

- (instancetype)initWithService:(SigningService *)service {
    NSParameterAssert(service);

    self = [super init];
    if (self) {
        _service = service;
    }
    return self;
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    (void)listener;
    NSParameterAssert(connection);

    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SigningServiceProtocol)];
    connection.exportedObject = self.service;
    [connection resume];
    return YES;
}

@end
