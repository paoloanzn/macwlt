#import <Foundation/Foundation.h>
#import <Security/Security.h>

#define WALLET_TAG "app.macwlt.signing.v1"

const CFOptionFlags KEY_ACCESS_FLAGS = kSecAccessControlPrivateKeyUsage 
                                     | kSecAccessControlBiometryAny; 

static NSString *hex(NSData *d) {
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
    const uint8_t *b = d.bytes;
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

static NSData *kWalletTag(void) {
    return [@WALLET_TAG dataUsingEncoding:NSUTF8StringEncoding];
}

static SecKeyRef makeSEKey(NSError **outError) {
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        KEY_ACCESS_FLAGS,
        &accessError
    );

    if (!access) { *outError = CFBridgingRelease(accessError); return NULL; }

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecPrivateKeyAttrs: @{
            (__bridge id)kSecAttrIsPermanent: @YES, // <-- persist the key
            (__bridge id)kSecAttrApplicationTag: kWalletTag(),
            (__bridge id)kSecAttrAccessControl: (__bridge id)access,
        },
        (__bridge id)kSecUseDataProtectionKeychain: @YES
    };
    
    CFErrorRef keyError = NULL;
    SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &keyError);
    CFRelease(access);
    if (!key && outError) *outError = CFBridgingRelease(keyError);

    return key;
}

static SecKeyRef loadOrCreateKey(NSError **outError) {
    NSDictionary *lookupQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: kWalletTag(),
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecReturnRef: @YES,
    };
    CFTypeRef item = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)lookupQuery, &item);
    if (status == errSecSuccess) return (SecKeyRef)item; // <-- key found

    // hands to makeSEKey -> creates and return a new key
    return makeSEKey(outError);
}

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        SecKeyRef key = loadOrCreateKey(&error);
        if (error) { NSLog(@"%@", error); return 1l; }

        NSData *msg = [@"Message" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *sig = CFBridgingRelease(SecKeyCreateSignature(
            key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)msg, NULL
        ));

        printf("SESignedMessage=%s\n", hex(sig).UTF8String);
        CFRelease(key);
    }
    return 0;
}
