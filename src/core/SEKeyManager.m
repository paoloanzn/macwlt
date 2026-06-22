/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SEKeyManager.h"

#define WALLET_TAG "app.macwlt.signing.v1"
#define SE_KEY_ERROR_DOMAIN "app.macwlt.signing.v1"

/*
 * Ad-hoc binaries cannot create permanent Secure Enclave keychain items.
 * Store the non-permanent token object's Secure Enclave blob instead; the
 * kSecAttrTokenOID SPI key is "toid".
 */
static CFStringRef kTokenOID(void) { return CFSTR("toid"); }

static const CFOptionFlags kKeyAccessFlags = kSecAccessControlPrivateKeyUsage
                                           | kSecAccessControlBiometryAny;

typedef NS_ENUM(NSInteger, SEKeyErrorCode) {
    SEKeyErrorMissingTokenOID = 1,
};

static NSError *seKeyError(SEKeyErrorCode code, NSString *message) {
    return [NSError errorWithDomain:@SE_KEY_ERROR_DOMAIN
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setError(NSError **outError, SEKeyErrorCode code, NSString *message) {
    if (outError) *outError = seKeyError(code, message);
}

static void setCFError(NSError **outError, CFErrorRef error) {
    if (!error) return;
    if (outError) *outError = CFBridgingRelease(error);
    else CFRelease(error);
}

static NSData *kWalletTag(void) {
    return [@WALLET_TAG dataUsingEncoding:NSUTF8StringEncoding];
}

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
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path error:NULL];
    return YES;
}

static SecKeyRef makeSEKey(NSData **outBlob, NSError **outError) {
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kKeyAccessFlags,
        &accessError
    );
    if (!access) {
        setCFError(outError, accessError);
        return NULL;
    }

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO,
            (__bridge id)kSecAttrApplicationTag: kWalletTag(),
            (__bridge id)kSecAttrAccessControl: (__bridge id)access,
        },
    };

    CFErrorRef keyError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &keyError);
    CFRelease(access);
    if (!key) {
        setCFError(outError, keyError);
        return NULL;
    }

    NSDictionary *keyAttrs = CFBridgingRelease(SecKeyCopyAttributes(key));
    NSData *blob = keyAttrs[(__bridge id)kTokenOID()];
    if (!blob) {
        setError(outError, SEKeyErrorMissingTokenOID,
                 @"Secure Enclave key has no token OID");
        CFRelease(key);
        return NULL;
    }
    if (outBlob) *outBlob = blob;
    return key;
}

static SecKeyRef reconstructSEKey(NSData *blob, NSError **outError) {
    NSDictionary *ref = @{
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kTokenOID(): blob,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO,
        },
    };
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)ref, &error);
    if (!key) setCFError(outError, error);
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
