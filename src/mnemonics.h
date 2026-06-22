/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptoError.h>

static NSArray<NSString *> *generateMnemonic(int entropyBits);
static NSData *mnemonicToSeed(NSArray<NSString *> *words, NSString *passphrase);
