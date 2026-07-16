/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletPublicKeyDerivation.h"

#include <wally_bip32.h>
#include <wally_core.h>
#include <wally_crypto.h>

#import <Security/Security.h>
#import <dispatch/dispatch.h>

NSString * const WalletPublicKeyDerivationErrorDomain = @"macwlt.WalletPublicKeyDerivation";

static const NSUInteger kCompressedPublicKeySize = 33;
static const NSUInteger kChainCodeSize = 32;

static NSError *publicDerivationError(WalletPublicKeyDerivationErrorCode code,
                                      NSString *message) {
    return [NSError errorWithDomain:WalletPublicKeyDerivationErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setPublicDerivationError(NSError **outError,
                                     WalletPublicKeyDerivationErrorCode code,
                                     NSString *message) {
    if (outError) *outError = publicDerivationError(code, message);
}

static BOOL ensureWallyInitialized(void) {
    static BOOL initialized = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        initialized = wally_init(0) == WALLY_OK;
    });
    return initialized;
}

static BOOL pathContainsHardenedComponent(NSString *derivationPath) {
    NSArray<NSString *> *components = [derivationPath componentsSeparatedByString:@"/"];
    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *component = components[i];
        if ([component hasSuffix:@"'"] ||
            [component hasSuffix:@"h"] ||
            [component hasSuffix:@"H"]) {
            return YES;
        }
    }
    return NO;
}

@implementation WalletPublicKeyDerivation

+ (nullable NSData *)randomChainCodeWithError:(NSError **)outError {
    NSMutableData *chainCode = [NSMutableData dataWithLength:kChainCodeSize];
    int status = SecRandomCopyBytes(kSecRandomDefault,
                                    chainCode.length,
                                    chainCode.mutableBytes);
    if (status != errSecSuccess) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorRandomFailed,
                                 @"Could not generate wallet chain code");
        return nil;
    }
    return [chainCode copy];
}

+ (nullable NSData *)publicKeyForRootCompressedPublicKey:(NSData *)rootCompressedPublicKey
                                               chainCode:(NSData *)chainCode
                                          derivationPath:(NSString *)derivationPath
                                                   error:(NSError **)outError {
    if (rootCompressedPublicKey.length != kCompressedPublicKeySize ||
        wally_ec_public_key_verify(rootCompressedPublicKey.bytes,
                                   rootCompressedPublicKey.length) != WALLY_OK) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorInvalidRootPublicKey,
                                 @"Root public key must be a valid compressed secp256k1 public key");
        return nil;
    }
    if (chainCode.length != kChainCodeSize) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorInvalidChainCode,
                                 @"Wallet chain code must be exactly 32 bytes");
        return nil;
    }
    if (![derivationPath isEqualToString:@"m"] &&
        ![derivationPath hasPrefix:@"m/"]) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorInvalidPath,
                                 @"Derivation path must start at m");
        return nil;
    }
    if ([derivationPath isEqualToString:@"m"]) {
        return [rootCompressedPublicKey copy];
    }
    if (pathContainsHardenedComponent(derivationPath)) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorUnsupportedHardenedPath,
                                 @"Hardened public derivation is not supported from the split root key");
        return nil;
    }
    if (!ensureWallyInitialized()) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorDerivationFailed,
                                 @"libwally initialization failed");
        return nil;
    }

    NSData *pathData = [derivationPath dataUsingEncoding:NSUTF8StringEncoding];
    if (!pathData) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorInvalidPath,
                                 @"Derivation path is not valid UTF-8");
        return nil;
    }

    struct ext_key root;
    struct ext_key child;
    int ret = bip32_key_init(BIP32_VER_MAIN_PUBLIC,
                             0,
                             0,
                             chainCode.bytes,
                             chainCode.length,
                             rootCompressedPublicKey.bytes,
                             rootCompressedPublicKey.length,
                             NULL,
                             0,
                             NULL,
                             0,
                             NULL,
                             0,
                             &root);
    if (ret == WALLY_OK) {
        ret = bip32_key_from_parent_path_str_n(&root,
                                               pathData.bytes,
                                               pathData.length,
                                               0,
                                               BIP32_FLAG_KEY_PUBLIC,
                                               &child);
    }
    if (ret != WALLY_OK) {
        setPublicDerivationError(outError,
                                 WalletPublicKeyDerivationErrorDerivationFailed,
                                 @"Could not derive public key for path");
        return nil;
    }

    return [NSData dataWithBytes:child.pub_key length:sizeof(child.pub_key)];
}

@end
