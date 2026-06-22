/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletViewController.h"
#import "WalletEnvelopeManager.h"
#import "hex.h"

#import <CommonCrypto/CommonDigest.h>

#define INPUT_PLACEHOLDER_STRING    "Message To Sign"
#define OUTPUT_PLACEHOLDER_STRING   "bootstrapping ephemeral wallet..."

@interface WalletViewController ()

@property (nonatomic, strong, nullable) NSData *walletEnvelope;

- (void)bootstrapWallet;

@end

@implementation WalletViewController

- (void)loadView {
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
            SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
            if (!key) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = [NSString stringWithFormat:@"error: %@", error];
                });
                return;
            }

            SecKeyRef publicKey = SecKeyCopyPublicKey(key);
            if (!publicKey) {
                CFRelease(key);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = @"error: could not copy Secure Enclave public key";
                });
                return;
            }

            NSData *envelope = [WalletEnvelopeManager walletBootstrap:publicKey error:&error];
            CFRelease(publicKey);
            CFRelease(key);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!envelope) {
                    self.output.stringValue = [NSString stringWithFormat:@"error: %@", error];
                    return;
                }

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
            SecKeyRef key = [SEKeyManager copyKeyWithError:&error];
            if (!key) { 
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = 
                        [NSString stringWithFormat:@"error: %@", error];
                });
                return;
            }

            NSData *msg = [text dataUsingEncoding:NSUTF8StringEncoding];
            uint8_t digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(msg.bytes, (CC_LONG)msg.length, digest);

            NSData *digestData = [NSData dataWithBytes:digest length:sizeof(digest)];
            // Sign the message by
            // -> Passing the envelope containing the wallet private key.
            // -> Passing the SE key to unwrap the envelop.
            NSData *sig = [WalletEnvelopeManager signWithSecp256k1:digestData
                                                           envelope:envelope
                                                                key:key
                                                              error:&error];
            CFRelease(key);

            if(sig) {
                NSString *h = hex(sig);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = h;
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.output.stringValue = [NSString stringWithFormat:@"error: %@", error];
                });
            }
        }
    );
}

@end
