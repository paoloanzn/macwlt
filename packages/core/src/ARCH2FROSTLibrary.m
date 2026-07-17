/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "ARCH2FROSTLibrary.h"

#include <dlfcn.h>

NSString * const ARCH2FROSTLibraryErrorDomain = @"macwlt.ARCH2FROSTLibrary";

typedef secp256k1_context *(*ContextCreateFn)(unsigned int flags);
typedef void (*ContextDestroyFn)(secp256k1_context *context);
typedef secp256k1_frost_vss_commitments *(*VSSCreateFn)(uint32_t threshold);
typedef void (*VSSDestroyFn)(secp256k1_frost_vss_commitments *commitments);
typedef int (*DKGBeginFn)(const secp256k1_context *,
                          secp256k1_frost_vss_commitments *,
                          secp256k1_frost_keygen_secret_share *,
                          uint32_t, uint32_t, uint32_t,
                          const unsigned char *, uint32_t);
typedef int (*DKGValidateFn)(const secp256k1_context *,
                             const secp256k1_frost_vss_commitments *,
                             const unsigned char *, uint32_t);
typedef int (*DKGFinalizeFn)(const secp256k1_context *,
                             secp256k1_frost_keypair *,
                             uint32_t, uint32_t,
                             const secp256k1_frost_keygen_secret_share *,
                             secp256k1_frost_vss_commitments **);
typedef int (*PublicKeyLoadFn)(secp256k1_frost_pubkey *, uint32_t, uint32_t,
                               const unsigned char *, const unsigned char *);
typedef int (*PublicKeySaveFn)(unsigned char *, unsigned char *,
                               const secp256k1_frost_pubkey *);
typedef int (*NonceInitFn)(const secp256k1_context *, secp256k1_frost_nonce *,
                           const secp256k1_frost_keypair *,
                           const unsigned char *, const unsigned char *);
typedef int (*SignFn)(const secp256k1_context *,
                      secp256k1_frost_signature_share *,
                      const unsigned char *, uint32_t, uint32_t,
                      const secp256k1_frost_keypair *,
                      secp256k1_frost_nonce *,
                      secp256k1_frost_nonce_commitment *);
typedef int (*AggregateFn)(const secp256k1_context *, unsigned char *,
                           const unsigned char *, uint32_t,
                           const secp256k1_frost_keypair *,
                           const secp256k1_frost_pubkey *,
                           secp256k1_frost_nonce_commitment *,
                           const secp256k1_frost_signature_share *, uint32_t);
typedef int (*VerifyFn)(const secp256k1_context *, const unsigned char *,
                        const unsigned char *, uint32_t,
                        const secp256k1_frost_pubkey *);

static NSError *libraryError(ARCH2FROSTLibraryErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ARCH2FROSTLibraryErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setLibraryError(NSError **outError,
                            ARCH2FROSTLibraryErrorCode code,
                            NSString *message) {
    if (outError) *outError = libraryError(code, message);
}

static NSURL *defaultLibraryURL(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"MACWLT_FROST_LIBRARY"];
    if (override.length > 0) return [NSURL fileURLWithPath:override];

    NSBundle *bundle = [NSBundle bundleForClass:ARCH2FROSTLibrary.class];
    NSURL *bundled = [bundle.privateFrameworksURL
        URLByAppendingPathComponent:@"libsecp256k1.6.dylib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bundled.path]) return bundled;

    NSString *workingPath = [NSFileManager.defaultManager.currentDirectoryPath
        stringByAppendingPathComponent:@"build/secp256k1-frost/lib/libsecp256k1.6.dylib"];
    return [NSURL fileURLWithPath:workingPath];
}

@implementation ARCH2FROSTLibrary {
    void *_handle;
    secp256k1_context *_context;
    ContextDestroyFn _contextDestroy;
    VSSCreateFn _vssCreate;
    VSSDestroyFn _vssDestroy;
    DKGBeginFn _dkgBegin;
    DKGValidateFn _dkgValidate;
    DKGFinalizeFn _dkgFinalize;
    PublicKeyLoadFn _publicKeyLoad;
    PublicKeySaveFn _publicKeySave;
    NonceInitFn _nonceInit;
    SignFn _sign;
    AggregateFn _aggregate;
    VerifyFn _verify;
}

+ (nullable instancetype)libraryWithError:(NSError **)outError {
    return [[self alloc] initWithDynamicLibraryURL:defaultLibraryURL() error:outError];
}

- (nullable instancetype)initWithDynamicLibraryURL:(NSURL *)dynamicLibraryURL
                                             error:(NSError **)outError {
    NSParameterAssert(dynamicLibraryURL.isFileURL);

    self = [super init];
    if (!self) return nil;

    _handle = dlopen(dynamicLibraryURL.fileSystemRepresentation,
                     RTLD_NOW | RTLD_LOCAL | RTLD_FIRST);
    if (!_handle) {
        NSString *message = [NSString stringWithFormat:@"Could not load FROST library at %@: %s",
                                                       dynamicLibraryURL.path,
                                                       dlerror() ?: "unknown error"];
        setLibraryError(outError, ARCH2FROSTLibraryErrorNotFound, message);
        return nil;
    }

#define LOAD_SYMBOL(variable, type, name) \
    do { \
        variable = (type)dlsym(_handle, name); \
        if (!variable) { \
            setLibraryError(outError, ARCH2FROSTLibraryErrorSymbolMissing, \
                            [NSString stringWithFormat:@"FROST library is missing %s", name]); \
            [self closeLibrary]; \
            return nil; \
        } \
    } while (0)

    ContextCreateFn contextCreate;
    LOAD_SYMBOL(contextCreate, ContextCreateFn, "secp256k1_context_create");
    LOAD_SYMBOL(_contextDestroy, ContextDestroyFn, "secp256k1_context_destroy");
    LOAD_SYMBOL(_vssCreate, VSSCreateFn, "secp256k1_frost_vss_commitments_create");
    LOAD_SYMBOL(_vssDestroy, VSSDestroyFn, "secp256k1_frost_vss_commitments_destroy");
    LOAD_SYMBOL(_dkgBegin, DKGBeginFn, "secp256k1_frost_keygen_dkg_begin");
    LOAD_SYMBOL(_dkgValidate, DKGValidateFn, "secp256k1_frost_keygen_dkg_commitment_validate");
    LOAD_SYMBOL(_dkgFinalize, DKGFinalizeFn, "secp256k1_frost_keygen_dkg_finalize");
    LOAD_SYMBOL(_publicKeyLoad, PublicKeyLoadFn, "secp256k1_frost_pubkey_load");
    LOAD_SYMBOL(_publicKeySave, PublicKeySaveFn, "secp256k1_frost_pubkey_save");
    LOAD_SYMBOL(_nonceInit, NonceInitFn, "secp256k1_frost_nonce_init");
    LOAD_SYMBOL(_sign, SignFn, "secp256k1_frost_sign");
    LOAD_SYMBOL(_aggregate, AggregateFn, "secp256k1_frost_aggregate");
    LOAD_SYMBOL(_verify, VerifyFn, "secp256k1_frost_verify");
#undef LOAD_SYMBOL

    _context = contextCreate(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
    if (!_context) {
        setLibraryError(outError, ARCH2FROSTLibraryErrorContextCreationFailed,
                        @"Could not create the FROST secp256k1 context");
        [self closeLibrary];
        return nil;
    }
    return self;
}

- (void)dealloc {
    [self closeLibrary];
}

- (void)closeLibrary {
    if (_context && _contextDestroy) _contextDestroy(_context);
    _context = NULL;
    if (_handle) dlclose(_handle);
    _handle = NULL;
}

- (const secp256k1_context *)context {
    return _context;
}

- (secp256k1_frost_vss_commitments *)createVSSCommitmentsWithThreshold:(uint32_t)threshold {
    return _vssCreate(threshold);
}

- (void)destroyVSSCommitments:(secp256k1_frost_vss_commitments *)commitments {
    if (commitments) _vssDestroy(commitments);
}

- (BOOL)beginDKGWithCommitments:(secp256k1_frost_vss_commitments *)commitments
                        shares:(secp256k1_frost_keygen_secret_share *)shares
                  participants:(uint32_t)participants
                     threshold:(uint32_t)threshold
                generatorIndex:(uint32_t)generatorIndex
                       context:(NSData *)context {
    return _dkgBegin(_context, commitments, shares, participants, threshold,
                     generatorIndex, context.bytes, (uint32_t)context.length) == 1;
}

- (BOOL)validateCommitment:(secp256k1_frost_vss_commitments *)commitment
                   context:(NSData *)context {
    return _dkgValidate(_context, commitment, context.bytes,
                        (uint32_t)context.length) == 1;
}

- (BOOL)finalizeDKGForParticipant:(uint32_t)participantIndex
                          shares:(const secp256k1_frost_keygen_secret_share *)shares
                     commitments:(secp256k1_frost_vss_commitments * const *)commitments
                         keypair:(secp256k1_frost_keypair *)keypair {
    return _dkgFinalize(_context, keypair, participantIndex, 2, shares,
                        (secp256k1_frost_vss_commitments **)commitments) == 1;
}

- (BOOL)loadPublicKey:(secp256k1_frost_pubkey *)publicKey
                index:(uint32_t)index
     participantCount:(uint32_t)participantCount
participantPublicKey33:(const unsigned char *)participantPublicKey33
     groupPublicKey33:(const unsigned char *)groupPublicKey33 {
    return _publicKeyLoad(publicKey, index, participantCount,
                          participantPublicKey33, groupPublicKey33) == 1;
}

- (BOOL)savePublicKey:(const secp256k1_frost_pubkey *)publicKey
participantPublicKey33:(unsigned char *)participantPublicKey33
     groupPublicKey33:(unsigned char *)groupPublicKey33 {
    return _publicKeySave(participantPublicKey33, groupPublicKey33, publicKey) == 1;
}

- (BOOL)initializeNonce:(secp256k1_frost_nonce *)nonce
                keypair:(const secp256k1_frost_keypair *)keypair
            bindingSeed:(const unsigned char *)bindingSeed
             hidingSeed:(const unsigned char *)hidingSeed {
    return _nonceInit(_context, nonce, keypair, bindingSeed, hidingSeed) == 1;
}

- (BOOL)signMessage:(NSData *)message
            keypair:(const secp256k1_frost_keypair *)keypair
              nonce:(secp256k1_frost_nonce *)nonce
        commitments:(secp256k1_frost_nonce_commitment *)commitments
     signatureShare:(secp256k1_frost_signature_share *)signatureShare {
    return _sign(_context, signatureShare, message.bytes, (uint32_t)message.length,
                 2, keypair, nonce, commitments) == 1;
}

- (BOOL)aggregateMessage:(NSData *)message
                 keypair:(const secp256k1_frost_keypair *)keypair
              publicKeys:(const secp256k1_frost_pubkey *)publicKeys
             commitments:(secp256k1_frost_nonce_commitment *)commitments
         signatureShares:(const secp256k1_frost_signature_share *)signatureShares
               signature:(unsigned char *)signature {
    return _aggregate(_context, signature, message.bytes, (uint32_t)message.length,
                      keypair, publicKeys, commitments, signatureShares, 2) == 1;
}

- (BOOL)verifySignature:(const unsigned char *)signature
                message:(NSData *)message
              publicKey:(const secp256k1_frost_pubkey *)publicKey {
    return _verify(_context, signature, message.bytes, (uint32_t)message.length,
                   publicKey) == 1;
}

@end
