/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "../core/SigningService.h"
#import "../core/SigningServiceListenerDelegate.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSError *error = nil;
        SigningService *service = [[SigningService alloc] initWithError:&error];
        if (!service) {
            NSLog(@"SigningService init failed: %@", error);
            return EXIT_FAILURE;
        }

        SigningServiceListenerDelegate *delegate =
            [[SigningServiceListenerDelegate alloc] initWithService:service];
        NSXPCListener *listener = [NSXPCListener serviceListener];
        listener.delegate = delegate;
        [listener resume];
    }
    return EXIT_FAILURE;
}
