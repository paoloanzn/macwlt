/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SEKeyManager.h"

#define WALLET_TAG "app.macwlt.signing.v1"

/***********************************************************************
* Secure Enclave token object persistence.
*
* Permanent Secure Enclave keys are stored in the data protection keychain,
* which requires a validated keychain access group. Ad-hoc binaries cannot
* provide that entitlement, and attempts to fake it are rejected before
* launch or by secd.
*
* Store no keychain item here. The key is created as a non-permanent Secure
* Enclave token key. Its token object ID contains the SE-wrapped private key,
* public key, and access control data. The blob is usable only on this Mac
* and only after the access control checks pass.
*
* Reopening passes that object ID back to SecKeyCreateRandomKey() with
* kSecAttrTokenIDSecureEnclave. kSecAttrTokenOID selects reconstruction of
* the token object instead of generation of a new key; kSecAttrIsPermanent
* remains false so nothing is filed in the keychain.
*
* kSecAttrTokenOID is Security SPI. Its CFString key is "toid".
**********************************************************************/
static CFStringRef kTokenOID(void) { return CFSTR("toid"); }

static const CFOptionFlags kKeyAccessFlags = kSecAccessControlPrivateKeyUsage
                                          | kSecAccessControlBiometryAny;

static NSData *kWalletTag(void) {
    return [@WALLET_TAG dataUsingEncoding:NSUTF8StringEncoding];
}

// Where we keep the SE-wrapped key blob. It is device-bound and ACL-gated, so
// the file alone cannot sign anything off this Mac or without the key's ACL.
static NSString *blobPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:
                     @"Library/Application Support/macwlt"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0700}
                                                    error:NULL];
    return [dir stringByAppendingPathComponent:@"se-token.blob"];
}

static NSData *loadStoredBlob(void) {
    return [NSData dataWithContentsOfFile:blobPath()];
}

static BOOL storeBlob(NSData *blob) {
    NSString *path = blobPath();
    if (![blob writeToFile:path options:NSDataWritingAtomic error:NULL]) return NO;
    // The blob is already SE-wrapped and device-bound; still, keep it owner-only.
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path error:NULL];
    return YES;
}

// Create a fresh Secure Enclave key (never persisted in the keychain) and
// return its SE-wrapped token blob via *outBlob.
static SecKeyRef makeSEKey(NSData **outBlob, NSError **outError) {
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kKeyAccessFlags,
        &accessError
    );
    if (!access) { if (outError) *outError = CFBridgingRelease(accessError); return NULL; }

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO, // never touch the keychain
            (__bridge id)kSecAttrApplicationTag: kWalletTag(),
            (__bridge id)kSecAttrAccessControl: (__bridge id)access,
        },
    };

    CFErrorRef keyError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &keyError);
    CFRelease(access);
    if (!key) { if (outError) *outError = CFBridgingRelease(keyError); return NULL; }

    NSDictionary *keyAttrs = CFBridgingRelease(SecKeyCopyAttributes(key));
    NSData *blob = keyAttrs[(__bridge id)kTokenOID()];
    if (!blob) {
        if (outError) *outError = [NSError errorWithDomain:@WALLET_TAG code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Secure Enclave key has no token OID"}];
        CFRelease(key);
        return NULL;
    }
    if (outBlob) *outBlob = blob;
    return key;
}

// Rebuild a SecKeyRef from a stored SE-wrapped blob. No key generation, no
// keychain: the SE just unwraps the blob into a usable token object.
static SecKeyRef reconstructSEKey(NSData *blob, NSError **outError) {
    NSDictionary *ref = @{
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kTokenOID(): blob,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO, // reconstruct only, do not file
        },
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)ref, &error);
    if (!key && outError) *outError = CFBridgingRelease(error);
    return key;
}

@implementation SEKeyManager

+ (SecKeyRef)copyKeyWithError:(NSError **)outError {
    NSData *stored = loadStoredBlob();
    if (stored) return reconstructSEKey(stored, outError);

    NSData *blob = nil;
    SecKeyRef key = makeSEKey(&blob, outError);
    if (!key) return NULL;
    if (!storeBlob(blob)) {
        NSLog(@"warning: could not persist SE key blob; it will not survive restart");
    }
    return key;
}

@end
