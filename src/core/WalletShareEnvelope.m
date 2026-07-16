/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WalletShareEnvelope.h"

#import "HardenedBuffer.h"
#import "SEKeyManager.h"
#import "SecureWipe.h"
#import "SigningShareSet.h"
#import "WalletEnvelopeManager.h"
#import "WalletPublicKeyDerivation.h"

#import <Security/Security.h>

#include <string.h>

NSString * const WalletShareEnvelopeErrorDomain = @"macwlt.WalletShareEnvelope";

static NSString * const kWalletShareEnvelopeFileName = @"wallet-share-envelope.plist";
static NSString * const kWalletShareEnvelopeVersionKey = @"version";
static NSString * const kWalletShareEnvelopeEnvelopeAKey = @"envelopeA";
static NSString * const kWalletShareEnvelopeEnvelopeBKey = @"envelopeB";
static NSString * const kWalletShareEnvelopeJointPublicKeyKey = @"jointCompressedPublicKey";
static NSString * const kWalletShareEnvelopeChainCodeKey = @"chainCode";
static const NSInteger kWalletShareEnvelopeLegacyVersion = 1;
static const NSInteger kWalletShareEnvelopeCurrentVersion = 2;

static NSError *walletShareEnvelopeError(WalletShareEnvelopeErrorCode code,
                                         NSString *message) {
    return [NSError errorWithDomain:WalletShareEnvelopeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setWalletShareEnvelopeError(NSError **outError,
                                        WalletShareEnvelopeErrorCode code,
                                        NSString *message) {
    if (outError) *outError = walletShareEnvelopeError(code, message);
}

static NSString *walletSupportDirectoryPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/macwlt"];
}

static NSURL *walletSupportDirectoryURL(void) {
    return [NSURL fileURLWithPath:walletSupportDirectoryPath() isDirectory:YES];
}

static BOOL errorIsPersistentEnvelopeNotFound(NSError *error) {
    return [error.domain isEqualToString:WalletShareEnvelopeErrorDomain] &&
        error.code == WalletShareEnvelopeErrorPersistentEnvelopeNotFound;
}

static NSData *validatedDataValue(NSDictionary<NSString *, id> *dictionary,
                                  NSString *key,
                                  NSUInteger expectedLength,
                                  NSError **outError) {
    id value = dictionary[key];
    if (![value isKindOfClass:NSData.class]) {
        NSString *message = [NSString stringWithFormat:@"Persistent wallet envelope is missing %@", key];
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    message);
        return nil;
    }

    NSData *data = (NSData *)value;
    if (expectedLength > 0 && data.length != expectedLength) {
        NSString *message = [NSString stringWithFormat:@"Persistent wallet envelope has invalid %@ length", key];
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    message);
        return nil;
    }
    if (expectedLength == 0 && data.length == 0) {
        NSString *message = [NSString stringWithFormat:@"Persistent wallet envelope has empty %@", key];
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    message);
        return nil;
    }
    return data;
}

static NSDictionary<NSString *, id> *validatedPersistentDictionary(id propertyList,
                                                                   NSError **outError) {
    if (![propertyList isKindOfClass:NSDictionary.class]) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    @"Persistent wallet envelope must be a dictionary");
        return nil;
    }

    NSDictionary<NSString *, id> *dictionary = (NSDictionary<NSString *, id> *)propertyList;
    id version = dictionary[kWalletShareEnvelopeVersionKey];
    if (![version isKindOfClass:NSNumber.class]) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    @"Persistent wallet envelope has an unsupported version");
        return nil;
    }
    NSInteger versionValue = ((NSNumber *)version).integerValue;
    if (versionValue != kWalletShareEnvelopeLegacyVersion &&
        versionValue != kWalletShareEnvelopeCurrentVersion) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidPersistentEnvelope,
                                    @"Persistent wallet envelope has an unsupported version");
        return nil;
    }
    return dictionary;
}

static SecKeyRef copyPublicKeyForPrivateKey(SecKeyRef privateKey,
                                            NSError **outError) CF_RETURNS_RETAINED {
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorMissingPublicKey,
                                    @"Could not copy Secure Enclave wrapper public key");
    }
    return publicKey;
}

static NSData *wrapShare(NSData *share,
                         SEKeyPurpose keyPurpose,
                         NSError **outError) {
    SecKeyRef privateKey = [SEKeyManager copyKeyForPurpose:keyPurpose error:outError];
    if (!privateKey) return nil;

    SecKeyRef publicKey = copyPublicKeyForPrivateKey(privateKey, outError);
    CFRelease(privateKey);
    if (!publicKey) return nil;

    NSData *envelope = [WalletEnvelopeManager envelopeWrap:share
                                                 publicKey:publicKey
                                                     error:outError];
    CFRelease(publicKey);
    return envelope;
}

static SEKeyPurpose keyPurposeForShare(WalletShareEnvelopeShare share) {
    switch (share) {
        case WalletShareEnvelopeShareA:
            return SEKeyPurposeSigningShareA;
        case WalletShareEnvelopeShareB:
            return SEKeyPurposeSigningShareB;
    }
    NSCAssert(NO, @"Unhandled wallet signing share");
    return SEKeyPurposeSigningShareA;
}

@implementation WalletShareEnvelope

+ (nullable instancetype)bootstrapWithError:(NSError **)outError {
    SigningShareSet *shareSet = [SigningShareSet generateWithError:outError];
    if (!shareSet) return nil;

    NSMutableData *shareA = [shareSet.shareA mutableCopy];
    NSMutableData *shareB = [shareSet.shareB mutableCopy];
    NSData *jointPublicKey = shareSet.jointCompressedPublicKey;
    NSData *chainCode = [WalletPublicKeyDerivation randomChainCodeWithError:outError];
    if (!chainCode) {
        secureWipe(shareA.mutableBytes, shareA.length);
        secureWipe(shareB.mutableBytes, shareB.length);
        return nil;
    }

    NSData *envelopeA = nil;
    NSData *envelopeB = nil;
    @try {
        envelopeA = wrapShare(shareA, SEKeyPurposeSigningShareA, outError);
        if (!envelopeA) return nil;

        envelopeB = wrapShare(shareB, SEKeyPurposeSigningShareB, outError);
        if (!envelopeB) return nil;
    } @finally {
        secureWipe(shareA.mutableBytes, shareA.length);
        secureWipe(shareB.mutableBytes, shareB.length);
    }

    return [[self alloc] initWithEnvelopeA:envelopeA
                                 envelopeB:envelopeB
                  jointCompressedPublicKey:jointPublicKey
                                  chainCode:chainCode];
}

+ (NSURL *)defaultStorageURL {
    return [walletSupportDirectoryURL() URLByAppendingPathComponent:kWalletShareEnvelopeFileName
                                                        isDirectory:NO];
}

+ (nullable instancetype)loadOrBootstrapFromDefaultStorageWithError:(NSError **)outError {
    NSURL *url = [self defaultStorageURL];
    NSError *loadError = nil;
    WalletShareEnvelope *loaded = [self loadFromURL:url error:&loadError];
    if (loaded) return loaded;

    if (!errorIsPersistentEnvelopeNotFound(loadError)) {
        if (outError) *outError = loadError;
        return nil;
    }

    WalletShareEnvelope *bootstrapped = [self bootstrapWithError:outError];
    if (!bootstrapped) return nil;

    if (![bootstrapped writeToURL:url error:outError]) return nil;
    return bootstrapped;
}

+ (nullable instancetype)loadFromURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url);
    NSParameterAssert(url.isFileURL);

    NSString *path = url.path;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorPersistentEnvelopeNotFound,
                                    @"Persistent wallet envelope was not found");
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
    if (!data) return nil;

    NSError *parseError = nil;
    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&parseError];
    if (!propertyList) {
        if (outError) *outError = parseError;
        return nil;
    }

    NSDictionary<NSString *, id> *dictionary = validatedPersistentDictionary(propertyList, outError);
    if (!dictionary) return nil;

    NSData *envelopeA = validatedDataValue(dictionary,
                                           kWalletShareEnvelopeEnvelopeAKey,
                                           0,
                                           outError);
    if (!envelopeA) return nil;

    NSData *envelopeB = validatedDataValue(dictionary,
                                           kWalletShareEnvelopeEnvelopeBKey,
                                           0,
                                           outError);
    if (!envelopeB) return nil;

    NSData *jointPublicKey = validatedDataValue(dictionary,
                                                kWalletShareEnvelopeJointPublicKeyKey,
                                                33,
                                                outError);
    if (!jointPublicKey) return nil;

    NSData *chainCode = nil;
    NSNumber *version = dictionary[kWalletShareEnvelopeVersionKey];
    if (version.integerValue >= kWalletShareEnvelopeCurrentVersion) {
        chainCode = validatedDataValue(dictionary,
                                       kWalletShareEnvelopeChainCodeKey,
                                       32,
                                       outError);
        if (!chainCode) return nil;
    }

    return [[self alloc] initWithEnvelopeA:envelopeA
                                 envelopeB:envelopeB
                  jointCompressedPublicKey:jointPublicKey
                                  chainCode:chainCode];
}

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                         envelopeB:(NSData *)envelopeB
          jointCompressedPublicKey:(NSData *)jointCompressedPublicKey {
    return [self initWithEnvelopeA:envelopeA
                         envelopeB:envelopeB
          jointCompressedPublicKey:jointCompressedPublicKey
                         chainCode:nil];
}

- (instancetype)initWithEnvelopeA:(NSData *)envelopeA
                         envelopeB:(NSData *)envelopeB
          jointCompressedPublicKey:(NSData *)jointCompressedPublicKey
                          chainCode:(NSData *)chainCode {
    NSParameterAssert(envelopeA.length > 0);
    NSParameterAssert(envelopeB.length > 0);
    NSParameterAssert(jointCompressedPublicKey.length == 33);
    NSParameterAssert(!chainCode || chainCode.length == 32);

    self = [super init];
    if (self) {
        _envelopeA = [envelopeA copy];
        _envelopeB = [envelopeB copy];
        _jointCompressedPublicKey = [jointCompressedPublicKey copy];
        _chainCode = [chainCode copy];
    }
    return self;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)outError {
    NSParameterAssert(url);
    NSParameterAssert(url.isFileURL);

    NSMutableDictionary<NSString *, id> *propertyList = [@{
        kWalletShareEnvelopeVersionKey: self.chainCode ? @(kWalletShareEnvelopeCurrentVersion) : @(kWalletShareEnvelopeLegacyVersion),
        kWalletShareEnvelopeEnvelopeAKey: self.envelopeA,
        kWalletShareEnvelopeEnvelopeBKey: self.envelopeB,
        kWalletShareEnvelopeJointPublicKeyKey: self.jointCompressedPublicKey,
    } mutableCopy];
    if (self.chainCode) propertyList[kWalletShareEnvelopeChainCodeKey] = self.chainCode;

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:outError];
    if (!data) return NO;

    NSURL *directoryURL = [url URLByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0700}
                                                        error:outError]) {
        return NO;
    }

    if (![data writeToURL:url options:NSDataWritingAtomic error:outError]) return NO;

    return [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                            ofItemAtPath:url.path
                                                   error:outError];
}

- (NSData *)envelopeForShare:(WalletShareEnvelopeShare)share {
    switch (share) {
        case WalletShareEnvelopeShareA:
            return self.envelopeA;
        case WalletShareEnvelopeShareB:
            return self.envelopeB;
    }
    NSAssert(NO, @"Unhandled wallet signing share");
    return self.envelopeA;
}

- (BOOL)unwrapShare:(WalletShareEnvelopeShare)share
 intoHardenedBuffer:(HardenedBuffer *)buffer
              error:(NSError **)outError {
    NSParameterAssert(buffer);
    if (buffer.state != HardenedBufferStateMasked) {
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorTargetBufferUnmasked,
                                    @"Signing shares may only be unwrapped into a masked hardened buffer");
        return NO;
    }

    SecKeyRef key = [SEKeyManager copyKeyForPurpose:keyPurposeForShare(share)
                                              error:outError];
    if (!key) return NO;

    NSMutableData *plain = [WalletEnvelopeManager envelopeUnwrap:[self envelopeForShare:share]
                                                      privateKey:key
                                                          error:outError];
    CFRelease(key);
    if (!plain) return NO;

    if (plain.length != 32 || plain.length > buffer.length) {
        secureWipe(plain.mutableBytes, plain.length);
        setWalletShareEnvelopeError(outError,
                                    WalletShareEnvelopeErrorInvalidShareLength,
                                    @"Unwrapped signing share must be exactly 32 bytes");
        return NO;
    }

    if (![buffer unmaskWithError:outError]) {
        secureWipe(plain.mutableBytes, plain.length);
        return NO;
    }

    memcpy([buffer mutableBytes], plain.bytes, plain.length);
    secureWipe(plain.mutableBytes, plain.length);
    return YES;
}

- (BOOL)performWithHardenedShareWindow:(HardenedShareWindow *)window
                              shareAUse:(HardenedShareWindowUseBlock)shareAUse
                              shareBUse:(HardenedShareWindowUseBlock)shareBUse
                                  error:(NSError **)outError {
    NSParameterAssert(window);
    return [window performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                 NSError **error) {
        return [self unwrapShare:WalletShareEnvelopeShareA
              intoHardenedBuffer:targetBuffer
                           error:error];
    } shareAUse:shareAUse
        shareBLoader:^BOOL(HardenedBuffer *targetBuffer, NSError **error) {
        return [self unwrapShare:WalletShareEnvelopeShareB
              intoHardenedBuffer:targetBuffer
                           error:error];
    } shareBUse:shareBUse
            error:outError];
}

@end
