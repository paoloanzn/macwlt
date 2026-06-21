/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "hex.h"
#import "se-key.h"

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
        if (!key) { NSLog(@"%@", error); return 1; }

        NSData *msg = [@"Message" dataUsingEncoding:NSUTF8StringEncoding];
        CFErrorRef sigError = NULL;
        NSData *sig = CFBridgingRelease(SecKeyCreateSignature(
            key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)msg, &sigError
        ));
        if (!sig) { NSLog(@"%@", (__bridge NSError *)sigError); CFRelease(key); return 1; }

        printf("SESignedMessage=%s\n", hex(sig).UTF8String);
        CFRelease(key);
    }
    return 0;
}
