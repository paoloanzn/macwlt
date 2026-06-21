/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletViewController.h"
#import "hex.h"

#define INPUT_PLACEHOLDER_STRING    "Message To Sign"
#define OUTPUT_PLACEHOLDER_STRING   "(no signature yet)"

@implementation WalletViewController

- (void)loadView {
    self.input = [NSTextField textFieldWithString:@INPUT_PLACEHOLDER_STRING];
    self.output = [NSTextField labelWithString:@OUTPUT_PLACEHOLDER_STRING];
    self.signButton = [NSButton buttonWithTitle:@"Sign" target:self action:@selector(doSign:)];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.input, self.signButton, self.output
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    self.view = stack;
}

- (void)doSign:(id)sender {
    NSString *text = self.input.stringValue;
    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^{
            NSError *error = nil;
            SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
            if (!key) { 
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = 
                        [NSString stringWithFormat:@"error: %@", error];
                });
                return;
            }

            NSData *msg = [text dataUsingEncoding:NSUTF8StringEncoding];
            NSData *sig = CFBridgingRelease(SecKeyCreateSignature(
                key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                (__bridge CFDataRef)msg, NULL
            ));
            CFRelease(key);

            if(sig) {
                NSString *h = hex(sig);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = h;
                });
            }
        }
    );
}

@end
