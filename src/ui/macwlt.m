/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <stdlib.h>
#import "../core/SEKeyManager.h"
#import "WalletViewController.h"

#define WINDOW_NAME "Macwlt"
#define APP_NAME    "macwlt"

static void die(NSError *err, NSString *errMsg) {
    NSInteger returnedErrorCode = 1;
    NSString *loggedErrorString = nil;

    if (errMsg) loggedErrorString = errMsg;
    if (err) { loggedErrorString = [err localizedDescription]; returnedErrorCode = [err code]; }

    NSLog(@"%@: error: %@; abort;", @APP_NAME, loggedErrorString);
    exit(returnedErrorCode);
}

int main(void) {
    @autoreleasepool {
        if (![SEKeyManager secureEnclaveAvailable]) {
            die(NULL, @"Secure Enclave is not available");
        }

        NSApplication *app = [NSApplication sharedApplication];
        BOOL success = [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        if (!success) die(NULL, @"Failed to set ActivationPolicy");

        NSRect contentRect = NSMakeRect(0, 0, 520, 220);
        WalletViewController *walletViewController = [WalletViewController new];
        walletViewController.preferredContentSize = contentRect.size;

        NSWindow *win = [[NSWindow alloc]
            initWithContentRect:contentRect
            styleMask:(NSWindowStyleMaskTitled |
                       NSWindowStyleMaskClosable) 
            backing:(NSBackingStoreBuffered) 
            defer:NO
        ];
        win.contentViewController = walletViewController;
        win.title = @WINDOW_NAME;
        [win center];
        [win makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
