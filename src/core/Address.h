/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// BIP-84 native SegWit (P2WPKH) address rendering.
//
// The pubkey-to-address pipeline: a compressed secp256k1 public key (33 bytes)
// is run through HASH160 = RIPEMD-160(SHA-256(pubkey)) to a 20-byte witness
// program, which is prefixed with witness version 0 and Bech32-encoded under the
// "bc" (mainnet) or "tb" (testnet) human-readable prefix — producing a bc1q…
// address for keys derived along m/84'/0'/account'/change/index.

// Return the P2WPKH address for `compressedPubKey` (33 bytes, prefix 0x02/0x03),
// using the "bc" HRP when `mainnet` is YES and "tb" otherwise. Returns nil if the
// key is not a well-formed compressed point.
NSString *_Nullable p2wpkhAddress(NSData *compressedPubKey, BOOL mainnet);

NS_ASSUME_NONNULL_END
