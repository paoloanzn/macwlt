/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import "SEKeyManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface WalletViewController : NSViewController

@property (nonatomic, strong) NSTextField   *input;
@property (nonatomic, strong) NSTextField   *output;
@property (nonatomic, strong) NSButton      *signButton;

- (void) loadView;
- (void) doSign:(id)sender;

@end


NS_ASSUME_NONNULL_END
