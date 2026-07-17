/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletViewController.h"
#import "WalletService.h"
#import "hex.h"

#define INPUT_PLACEHOLDER_STRING    "Message To Sign"
#define OUTPUT_PLACEHOLDER_STRING   "bootstrapping ephemeral wallet..."

@interface WalletViewController ()

@property (nonatomic, strong) NSTextField *input;
@property (nonatomic, strong) NSTextField *output;
@property (nonatomic, strong) NSButton *signButton;
@property (nonatomic, strong) WalletService *walletService;
@property (nonatomic, copy, nullable) NSData *walletEnvelope;

- (void)bootstrapWallet;
- (void)showOutput:(NSString *)message;
- (void)showError:(NSError *)error;
- (void)doSign:(id)sender;

@end

@implementation WalletViewController

- (void)showOutput:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.output.stringValue = message;
    });
}

- (void)showError:(NSError *)error {
    [self showOutput:[NSString stringWithFormat:@"error: %@", error]];
}

- (void)loadView {
    self.walletService = [[WalletService alloc] init];
    self.input = [NSTextField textFieldWithString:@INPUT_PLACEHOLDER_STRING];
    self.output = [NSTextField labelWithString:@OUTPUT_PLACEHOLDER_STRING];
    self.signButton = [NSButton buttonWithTitle:@"Sign" target:self action:@selector(doSign:)];
    self.signButton.enabled = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        self.input, self.signButton, self.output
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    self.view = stack;

    [self bootstrapWallet];
}

- (void)bootstrapWallet {
    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^{
            NSError *error = nil;
            NSData *envelope = [self.walletService bootstrapWalletWithError:&error];
            if (!envelope) {
                [self showError:error];
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                self.walletEnvelope = envelope;
                self.signButton.enabled = YES;
                self.output.stringValue = @"ephemeral wallet ready";
            });
        }
    );
}

- (void)doSign:(id)sender {
    NSData *envelope = self.walletEnvelope;
    if (!envelope) {
        self.output.stringValue = @"error: wallet is not ready";
        return;
    }

    NSString *text = self.input.stringValue;
    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^{
            NSError *error = nil;
            NSData *sig = [self.walletService signatureForMessage:text
                                                         envelope:envelope
                                                            error:&error];

            if (sig) {
                [self showOutput:hex(sig)];
            } else {
                [self showError:error];
            }
        }
    );
}

@end
