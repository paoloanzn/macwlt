/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SEKeyManager.h"

#define SE_KEY_ERROR_DOMAIN "app.macwlt.signing.v1"

/*
 * Ad-hoc binaries cannot create permanent Secure Enclave keychain items.
 * Store the non-permanent token object's Secure Enclave blob instead; the
 * kSecAttrTokenOID SPI key is "toid".
 */
static CFStringRef kTokenOID(void) { return CFSTR("toid"); }

typedef struct {
    const char *tag;
    NSString *blobName;
    CFOptionFlags accessFlags;
} SEKeyPurposeConfig;

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

static SEKeyPurposeConfig configForPurpose(SEKeyPurpose purpose) {
    switch (purpose) {
        case SEKeyPurposeLegacyEnvelope:
            return (SEKeyPurposeConfig){
                "app.macwlt.signing.v1",
                @"se-token.blob",
                kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryAny,
            };
        case SEKeyPurposeSigningShareA:
            return (SEKeyPurposeConfig){
                "app.macwlt.signing-share-a.v1",
                @"se-token-A.blob",
                kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryCurrentSet,
            };
        case SEKeyPurposeSigningShareB:
            return (SEKeyPurposeConfig){
                "app.macwlt.signing-share-b.v1",
                @"se-token-B.blob",
                kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryCurrentSet,
            };
    }
    NSCAssert(NO, @"Unhandled Secure Enclave key purpose");
    return (SEKeyPurposeConfig){
        "app.macwlt.signing.v1",
        @"se-token.blob",
        kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryAny,
    };
}

static NSString *blobDirectoryPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/macwlt"];
}

static NSString *blobPathForPurpose(SEKeyPurpose purpose) {
    SEKeyPurposeConfig config = configForPurpose(purpose);
    return [blobDirectoryPath() stringByAppendingPathComponent:config.blobName];
}

static NSString * _Nullable ensureBlobDirectory(NSError **outError) {
    NSString *dir = blobDirectoryPath();
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                        withIntermediateDirectories:YES
                                                         attributes:@{NSFilePosixPermissions: @0700}
                                                              error:outError];
    return ok ? dir : nil;
}

static NSData *loadStoredBlobForPurpose(SEKeyPurpose purpose, NSError **outError) {
    NSString *path = blobPathForPurpose(purpose);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [NSData dataWithContentsOfFile:path
                                  options:0
                                    error:outError];
}

static BOOL storeBlobForPurpose(NSData *blob, SEKeyPurpose purpose, NSError **outError) {
    if (!ensureBlobDirectory(outError)) return NO;

    NSString *path = blobPathForPurpose(purpose);
    if (![blob writeToFile:path options:NSDataWritingAtomic error:outError]) return NO;
    if (![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                          ofItemAtPath:path
                                                 error:outError]) {
        return NO;
    }
    return YES;
}

static NSData *tagDataForPurpose(SEKeyPurpose purpose) {
    SEKeyPurposeConfig config = configForPurpose(purpose);
    NSString *tag = [NSString stringWithUTF8String:config.tag];
    NSCAssert(tag.length > 0, @"Secure Enclave key tag must be valid UTF-8");
    return [tag dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *keychainQueryForPurpose(SEKeyPurpose purpose, BOOL returnRef) {
    NSMutableDictionary *query = [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: tagDataForPurpose(purpose),
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecUseDataProtectionKeychain: @YES,
    } mutableCopy];
    if (returnRef) query[(__bridge id)kSecReturnRef] = @YES;
    return query;
}

static SecKeyRef copyPermanentSEKeyForPurpose(SEKeyPurpose purpose,
                                              NSError **outError) CF_RETURNS_RETAINED {
    CFTypeRef item = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)keychainQueryForPurpose(purpose, YES),
                                          &item);
    if (status == errSecSuccess) return (SecKeyRef)item;
    if (status != errSecItemNotFound) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:status
                                        userInfo:@{NSLocalizedDescriptionKey: @"Could not load Secure Enclave key"}];
        }
        return NULL;
    }

    SEKeyPurposeConfig config = configForPurpose(purpose);
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        config.accessFlags,
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
        (__bridge id)kSecUseDataProtectionKeychain: @YES,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @YES,
            (__bridge id)kSecAttrApplicationTag: tagDataForPurpose(purpose),
            (__bridge id)kSecAttrAccessControl: (__bridge id)access,
        },
    };

    CFErrorRef keyError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &keyError);
    CFRelease(access);
    if (!key) setCFError(outError, keyError);
    return key;
}

static SecKeyRef makeSEKeyForPurpose(SEKeyPurpose purpose,
                                     NSData **outBlob,
                                     NSError **outError) {
    SEKeyPurposeConfig config = configForPurpose(purpose);
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        config.accessFlags,
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
            (__bridge id)kSecAttrApplicationTag: tagDataForPurpose(purpose),
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

static BOOL seProbeFailureMeansUnavailable(CFErrorRef error) {
    return error && CFErrorGetCode(error) == errSecUnimplemented;
}

static BOOL probeSecureEnclaveAvailability(void) {
    /*
     * Keep this probe close to makeSEKey's Secure Enclave generation path, but
     * do not share the biometric access-control attributes: startup probing must
     * stay non-interactive even though the real wallet key requires biometrics.
     */
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @NO,
        },
    };

    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &error);
    if (key) {
        if (error) CFRelease(error);
        CFRelease(key);
        return YES;
    }

    BOOL unavailable = seProbeFailureMeansUnavailable(error);
    if (error) CFRelease(error);
    return !unavailable;
}

@implementation SEKeyManager

+ (BOOL)secureEnclaveAvailable {
    return probeSecureEnclaveAvailability();
}

+ (SecKeyRef)copyKeyWithError:(NSError **)outError {
    return [self copyKeyForPurpose:SEKeyPurposeLegacyEnvelope error:outError];
}

+ (SecKeyRef)copyKeyForPurpose:(SEKeyPurpose)purpose error:(NSError **)outError {
    SecKeyRef permanentKey = copyPermanentSEKeyForPurpose(purpose, NULL);
    if (permanentKey) return permanentKey;

    NSError *storageError = nil;
    NSData *stored = loadStoredBlobForPurpose(purpose, &storageError);
    if (storageError) {
        if (outError) *outError = storageError;
        return NULL;
    }
    if (stored) return reconstructSEKey(stored, outError);

    NSData *blob = nil;
    SecKeyRef key = makeSEKeyForPurpose(purpose, &blob, outError);
    if (!key) return NULL;
    if (!storeBlobForPurpose(blob, purpose, outError)) {
        CFRelease(key);
        return NULL;
    }
    return key;
}

+ (BOOL)deleteAllManagedKeysWithError:(NSError **)outError {
    SEKeyPurpose purposes[] = {
        SEKeyPurposeLegacyEnvelope,
        SEKeyPurposeSigningShareA,
        SEKeyPurposeSigningShareB,
    };
    for (NSUInteger index = 0; index < sizeof(purposes) / sizeof(purposes[0]); index++) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)keychainQueryForPurpose(purposes[index], NO));
        (void)status;

        NSString *blobPath = blobPathForPurpose(purposes[index]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:blobPath] &&
            ![[NSFileManager defaultManager] removeItemAtPath:blobPath error:outError]) {
            return NO;
        }
    }
    return YES;
}

@end
