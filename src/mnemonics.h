/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

// Generate a BIP-39 mnemonic for the given entropy size (128–256 bits, a
// multiple of 32). Returns nil if the entropy size is invalid or the embedded
// wordlist cannot be loaded.
NSArray<NSString *> *generateMnemonic(int entropyBits);

// Derive the 64-byte BIP-39 seed from a mnemonic and optional passphrase.
// Returns nil if key derivation fails.
NSData *mnemonicToSeed(NSArray<NSString *> *words, NSString *passphrase);
