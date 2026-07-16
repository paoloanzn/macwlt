/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

#import "../src/core/Address.h"
#import "../src/core/HardenedBuffer.h"
#import "../src/core/HardenedShareWindow.h"
#import "../src/core/PSBT.h"
#import "../src/core/SigningService.h"
#import "../src/core/SigningServiceClient.h"
#import "../src/core/SigningServiceListenerDelegate.h"
#import "../src/core/SigningServiceProtocol.h"
#import "../src/core/SigningShareSet.h"
#import "../src/core/WalletAddressDerivation.h"
#import "../src/core/WalletPublicKeyDerivation.h"
#import "../src/core/WalletSigner.h"
#import "../src/core/WalletShareEnvelope.h"
#import "../src/core/hex.h"

#include "../src/core/macwlt.h"
#include <secp256k1.h>
#include <setjmp.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <wally_bip32.h>
#include <wally_bip39.h>
#include <wally_core.h>
#include <wally_crypto.h>

static void fail(NSString *message) {
    NSLog(@"%@", message);
    exit(1);
}

static void expect(BOOL condition, NSString *message) {
    if (!condition) fail(message);
}

static NSData *dataFromHex(NSString *string) {
    NSMutableData *data = [NSMutableData dataWithCapacity:string.length / 2];
    for (NSUInteger i = 0; i + 1 < string.length; i += 2) {
        NSString *byteString = [string substringWithRange:NSMakeRange(i, 2)];
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        expect([scanner scanHexInt:&byte],
               [NSString stringWithFormat:@"invalid hex byte %@", byteString]);
        uint8_t value = (uint8_t)byte;
        [data appendBytes:&value length:sizeof(value)];
    }
    return data;
}

static NSData *scalarData(uint8_t value) {
    NSMutableData *data = [NSMutableData dataWithLength:32];
    uint8_t *bytes = data.mutableBytes;
    bytes[31] = value;
    return data;
}

static NSData *compressedPublicKeyForSecret(NSData *secret) {
    secp256k1_context *ctx = wally_get_secp_context();
    expect(ctx != NULL, @"secp256k1 context unavailable");

    secp256k1_pubkey pubkey;
    expect(secp256k1_ec_pubkey_create(ctx, &pubkey, secret.bytes),
           @"secp256k1_ec_pubkey_create failed");

    uint8_t compressed[33];
    size_t compressedLength = sizeof(compressed);
    expect(secp256k1_ec_pubkey_serialize(ctx,
                                         compressed,
                                         &compressedLength,
                                         &pubkey,
                                         SECP256K1_EC_COMPRESSED),
           @"secp256k1_ec_pubkey_serialize failed");
    expect(compressedLength == sizeof(compressed),
           @"unexpected compressed public key length");
    return [NSData dataWithBytes:compressed length:sizeof(compressed)];
}

static NSData *privateKeyByMultiplying(NSData *a, NSData *b) {
    NSMutableData *out = [NSMutableData dataWithLength:32];
    expect(wally_ec_scalar_multiply(a.bytes, a.length,
                                    b.bytes, b.length,
                                    out.mutableBytes, out.length) == WALLY_OK,
           @"test scalar multiply failed");
    return out;
}

static NSData *privateKeyByAdding(NSData *a, NSData *b) {
    NSMutableData *out = [NSMutableData dataWithLength:32];
    expect(wally_ec_scalar_add(a.bytes, a.length,
                               b.bytes, b.length,
                               out.mutableBytes, out.length) == WALLY_OK,
           @"test scalar add failed");
    return out;
}

static NSURL *temporaryTestFileURL(NSString *name) {
    NSString *directory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    return [[NSURL fileURLWithPath:directory isDirectory:YES]
        URLByAppendingPathComponent:name
                        isDirectory:NO];
}

static sigjmp_buf maskedReadJump;
static volatile sig_atomic_t expectingMaskedReadSignal = 0;

static void maskedReadSignalHandler(int signalNumber) {
    if (expectingMaskedReadSignal) siglongjmp(maskedReadJump, signalNumber);
    _exit(128 + signalNumber);
}

static BOOL readTriggersProtectionFault(volatile uint8_t *address) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = maskedReadSignalHandler;
    sigemptyset(&action.sa_mask);

    struct sigaction previousSEGV;
    struct sigaction previousBUS;
    sigaction(SIGSEGV, &action, &previousSEGV);
    sigaction(SIGBUS, &action, &previousBUS);

    int signalNumber = sigsetjmp(maskedReadJump, 1);
    if (signalNumber == 0) {
        expectingMaskedReadSignal = 1;
        volatile uint8_t value = *address;
        (void)value;
        expectingMaskedReadSignal = 0;
        sigaction(SIGSEGV, &previousSEGV, NULL);
        sigaction(SIGBUS, &previousBUS, NULL);
        return NO;
    }

    expectingMaskedReadSignal = 0;
    sigaction(SIGSEGV, &previousSEGV, NULL);
    sigaction(SIGBUS, &previousBUS, NULL);
    return signalNumber == SIGSEGV || signalNumber == SIGBUS;
}

@interface MockXPCConnection : NSObject
@property (nonatomic, strong) NSXPCInterface *exportedInterface;
@property (nonatomic, strong) id exportedObject;
@property (nonatomic, readonly) BOOL resumed;
- (void)resume;
@end

@implementation MockXPCConnection {
    BOOL _resumed;
}

- (void)resume {
    _resumed = YES;
}

- (BOOL)resumed {
    return _resumed;
}

@end

static void testHex(void) {
    const uint8_t bytes[] = {0x00, 0xab, 0xff};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    expect([hex(data) isEqualToString:@"00abff"], @"hex encoding failed");
}

static void testBIP39MnemonicSeed(void) {
    NSArray<NSString *> *words = @[
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"abandon",
        @"abandon", @"abandon", @"abandon", @"about",
    ];
    NSString *mnemonic = [words componentsJoinedByString:@" "];
    uint8_t seedBytes[BIP39_SEED_LEN_512];
    int ret = bip39_mnemonic_to_seed512(mnemonic.UTF8String, "TREZOR",
                                        seedBytes, sizeof(seedBytes));
    NSData *seed = ret == WALLY_OK ? [NSData dataWithBytes:seedBytes
                                                     length:sizeof(seedBytes)] : nil;
    NSString *expected =
        @"c55257c360c07c72029aebc1b53c05ed"
        @"0362ada38ead3e3e9efa3708e5349553"
        @"1f09a6987599d18264c1e1c92f2cf141"
        @"630c7a3c4ab7c81b2f001698e7463b04";
    expect(seed != nil, @"BIP-39 seed derivation returned nil");
    expect([hex(seed) isEqualToString:expected], @"BIP-39 seed vector failed");
}

static void testP2WPKHAddress(void) {
    NSData *compressedPublicKey = dataFromHex(
        @"0279be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
    );
    NSString *address = p2wpkhAddress(compressedPublicKey, YES);
    expect([address isEqualToString:@"bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"],
           [NSString stringWithFormat:@"P2WPKH address vector failed: %@", address]);
}

static void testEthereumAddress(void) {
    NSData *generatorPublicKey = dataFromHex(
        @"79be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
        @"483ada7726a3c4655da4fbfc0e1108a8"
        @"fd17b448a68554199c47d08ffb10d4b8"
    );
    NSString *address = ethereumAddress(generatorPublicKey);
    expect([address isEqualToString:@"0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"],
           @"Ethereum address vector failed");
}

static void testPSBTInvalidData(void) {
    NSError *error = nil;
    PSBT *psbt = [PSBT psbtWithData:[@"not a psbt" dataUsingEncoding:NSUTF8StringEncoding]
                              error:&error];
    expect(psbt == nil, @"invalid PSBT data unexpectedly parsed");
    expect(error != nil, @"invalid PSBT data did not set NSError");
}

static void testHardenedBufferMasksMemory(void) {
    NSError *error = nil;
    HardenedBuffer *buffer = [HardenedBuffer bufferWithLength:32 error:&error];
    expect(buffer != nil,
           [NSString stringWithFormat:@"hardened buffer allocation failed: %@", error]);
    expect(buffer.length == 32, @"hardened buffer reported wrong usable length");
    expect(buffer.state == HardenedBufferStateMasked,
           @"hardened buffer should start masked");

    expect([buffer unmaskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer unmask failed: %@", error]);
    expect(buffer.state == HardenedBufferStateUnmasked,
           @"hardened buffer should report unmasked state");

    uint8_t *bytes = [buffer mutableBytes];
    bytes[0] = 0xa5;
    expect(bytes[0] == 0xa5, @"hardened buffer write/read while unmasked failed");

    expect([buffer maskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer mask failed: %@", error]);
    expect(buffer.state == HardenedBufferStateMasked,
           @"hardened buffer should report masked state");
    expect(readTriggersProtectionFault(bytes),
           @"masked hardened buffer memory remained readable");
}

static void testHardenedBufferWipeAndMask(void) {
    NSError *error = nil;
    HardenedBuffer *buffer = [HardenedBuffer bufferWithLength:32 error:&error];
    expect(buffer != nil,
           [NSString stringWithFormat:@"hardened buffer allocation failed: %@", error]);
    expect([buffer unmaskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer unmask failed: %@", error]);

    uint8_t *bytes = [buffer mutableBytes];
    memset(bytes, 0x7b, 32);
    expect([buffer wipeAndMaskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer wipe failed: %@", error]);
    expect(buffer.state == HardenedBufferStateMasked,
           @"hardened buffer should be masked after wipe");

    expect([buffer unmaskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer unmask after wipe failed: %@", error]);
    bytes = [buffer mutableBytes];
    for (NSUInteger i = 0; i < 32; i++) {
        expect(bytes[i] == 0, @"hardened buffer retained data after wipe");
    }
    expect([buffer maskWithError:&error],
           [NSString stringWithFormat:@"hardened buffer remask failed: %@", error]);
}

static BOOL loadSharePattern(HardenedBuffer *buffer, uint8_t pattern, NSError **outError) {
    if (![buffer unmaskWithError:outError]) return NO;
    memset([buffer mutableBytes], pattern, buffer.length);
    return YES;
}

static void testHardenedShareWindowSequencing(void) {
    NSError *error = nil;
    HardenedShareWindow *window = [HardenedShareWindow windowWithShareLength:32
                                                                       error:&error];
    expect(window != nil,
           [NSString stringWithFormat:@"share window allocation failed: %@", error]);

    NSMutableArray<NSString *> *events = [NSMutableArray array];
    BOOL ok = [window performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                    NSError **outError) {
        expect(window.shareAState == HardenedBufferStateMasked,
               @"share A should be masked before loading A");
        expect(window.shareBState == HardenedBufferStateMasked,
               @"share B should be masked before loading A");
        [events addObject:@"loadA"];
        return loadSharePattern(targetBuffer, 0xa1, outError);
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)outError;
        expect(shareLength == 32, @"share A use saw wrong length");
        expect(shareBytes[0] == 0xa1, @"share A use saw wrong byte");
        expect(window.shareAState == HardenedBufferStateUnmasked,
               @"share A should be unmasked during A use");
        expect(window.shareBState == HardenedBufferStateMasked,
               @"share B should be masked during A use");
        [events addObject:@"useA"];
        return YES;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        expect(window.shareAState == HardenedBufferStateMasked,
               @"share A should be masked before loading B");
        expect(window.shareBState == HardenedBufferStateMasked,
               @"share B should be masked before loading B");
        [events addObject:@"loadB"];
        return loadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)outError;
        expect(shareLength == 32, @"share B use saw wrong length");
        expect(shareBytes[0] == 0xb2, @"share B use saw wrong byte");
        expect(window.shareAState == HardenedBufferStateMasked,
               @"share A should be masked during B use");
        expect(window.shareBState == HardenedBufferStateUnmasked,
               @"share B should be unmasked during B use");
        [events addObject:@"useB"];
        return YES;
    } error:&error];

    expect(ok, [NSString stringWithFormat:@"share window sequencing failed: %@", error]);
    expect(window.shareAState == HardenedBufferStateMasked,
           @"share A should be masked after sequencing");
    expect(window.shareBState == HardenedBufferStateMasked,
           @"share B should be masked after sequencing");
    expect([events isEqualToArray:@[@"loadA", @"useA", @"loadB", @"useB"]],
           @"share window events ran in the wrong order");
}

static void testHardenedShareWindowMasksAfterFailure(void) {
    NSError *error = nil;
    HardenedShareWindow *window = [HardenedShareWindow windowWithShareLength:32
                                                                       error:&error];
    expect(window != nil,
           [NSString stringWithFormat:@"share window allocation failed: %@", error]);

    BOOL ok = [window performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                    NSError **outError) {
        return loadSharePattern(targetBuffer, 0xa1, outError);
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        if (outError) {
            *outError = [NSError errorWithDomain:@"macwlt.tests"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"expected failure"}];
        }
        return NO;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        return loadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        fail(@"share B should not run after share A failure");
        return NO;
    } error:&error];

    expect(!ok, @"share window unexpectedly succeeded after use failure");
    expect([error.domain isEqualToString:@"macwlt.tests"],
           @"share window did not preserve operation failure error");
    expect(window.shareAState == HardenedBufferStateMasked,
           @"share A should be masked after failure");
    expect(window.shareBState == HardenedBufferStateMasked,
           @"share B should remain masked after failure");
}

static void testHardenedShareWindowRejectsClosedLoader(void) {
    NSError *error = nil;
    HardenedShareWindow *window = [HardenedShareWindow windowWithShareLength:32
                                                                       error:&error];
    expect(window != nil,
           [NSString stringWithFormat:@"share window allocation failed: %@", error]);

    BOOL ok = [window performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                    NSError **outError) {
        (void)targetBuffer;
        (void)outError;
        return YES;
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        fail(@"share A use should not run when loader leaves buffer masked");
        return NO;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        return loadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        return YES;
    } error:&error];

    expect(!ok, @"share window unexpectedly accepted a closed loader");
    expect([error.domain isEqualToString:HardenedShareWindowErrorDomain],
           @"closed loader returned wrong error domain");
    expect(error.code == HardenedShareWindowErrorLoaderDidNotUnmask,
           @"closed loader returned wrong error code");
    expect(window.shareAState == HardenedBufferStateMasked,
           @"share A should stay masked after closed loader");
    expect(window.shareBState == HardenedBufferStateMasked,
           @"share B should stay masked after closed loader");
}

static void testSigningShareSetKnownPublicKey(void) {
    NSData *one = scalarData(1);
    NSData *two = scalarData(2);

    NSError *error = nil;
    NSData *joint = [SigningShareSet jointCompressedPublicKeyForShareA:one
                                                                shareB:two
                                                                 error:&error];
    expect(joint != nil,
           [NSString stringWithFormat:@"joint public key failed: %@", error]);
    expect([joint isEqualToData:compressedPublicKeyForSecret(two)],
           @"joint public key with share A = 1 should match share B public key");
}

static void testSigningShareSetRejectsInvalidShare(void) {
    NSData *zero = scalarData(0);
    NSData *one = scalarData(1);

    NSError *error = nil;
    NSData *joint = [SigningShareSet jointCompressedPublicKeyForShareA:zero
                                                                shareB:one
                                                                 error:&error];
    expect(joint == nil, @"zero signing share unexpectedly accepted");
    expect([error.domain isEqualToString:SigningShareSetErrorDomain],
           @"invalid signing share returned wrong error domain");
    expect(error.code == SigningShareSetErrorInvalidShare,
           @"invalid signing share returned wrong error code");
}

static void testSigningShareSetGeneratedCommutative(void) {
    NSError *error = nil;
    SigningShareSet *shareSet = [SigningShareSet generateWithError:&error];
    expect(shareSet != nil,
           [NSString stringWithFormat:@"share generation failed: %@", error]);
    expect(shareSet.shareA.length == 32, @"share A length is not 32 bytes");
    expect(shareSet.shareB.length == 32, @"share B length is not 32 bytes");
    expect(shareSet.jointCompressedPublicKey.length == 33,
           @"joint public key length is not 33 bytes");

    NSData *swapped = [SigningShareSet jointCompressedPublicKeyForShareA:shareSet.shareB
                                                                  shareB:shareSet.shareA
                                                                   error:&error];
    expect([swapped isEqualToData:shareSet.jointCompressedPublicKey],
           @"multiplicative share public key should be commutative");
}

static void testWalletSignerSignsWithSplitShares(void) {
    NSData *shareA = scalarData(2);
    NSData *shareB = scalarData(3);
    NSData *tweak = scalarData(5);
    NSData *digest = dataFromHex(@"0102030405060708090a0b0c0d0e0f10"
                                 @"1112131415161718191a1b1c1d1e1f20");
    NSData *parentKey = privateKeyByMultiplying(shareA, shareB);
    NSData *childKey = privateKeyByAdding(parentKey, tweak);
    NSData *publicKey = compressedPublicKeyForSecret(childKey);

    NSError *error = nil;
    WalletECDSASignature *signature = [WalletSigner signatureForDigest:digest
                                                                 shareA:shareA
                                                                 shareB:shareB
                                                                  tweak:tweak
                                                                  error:&error];
    expect(signature != nil,
           [NSString stringWithFormat:@"split signer failed: %@", error]);
    expect(signature.compactSignature.length == 64,
           @"split signer returned wrong compact signature length");
    expect(signature.derSignature.length > 0,
           @"split signer returned empty DER signature");
    expect((signature.recoveryID & ~3) == 0,
           @"split signer returned invalid recovery id");
    expect(wally_ec_sig_verify(publicKey.bytes,
                               publicKey.length,
                               digest.bytes,
                               digest.length,
                               EC_FLAG_ECDSA,
                               signature.compactSignature.bytes,
                               signature.compactSignature.length) == WALLY_OK,
           @"split signer signature did not verify against equivalent public key");
}

static void testWalletPublicKeyDerivationMatchesWally(void) {
    NSData *seed = dataFromHex(@"000102030405060708090a0b0c0d0e0f");

    struct ext_key root;
    struct ext_key child;
    memset(&root, 0, sizeof(root));
    memset(&child, 0, sizeof(child));

    int ret = bip32_key_from_seed(seed.bytes, seed.length,
                                  BIP32_VER_MAIN_PRIVATE, 0, &root);
    expect(ret == WALLY_OK, @"BIP32 test root derivation failed");
    ret = bip32_key_from_parent_path_str(&root,
                                         "m/0/1",
                                         0,
                                         BIP32_FLAG_KEY_PUBLIC,
                                         &child);
    expect(ret == WALLY_OK, @"BIP32 public child derivation failed");

    NSData *rootPublicKey = [NSData dataWithBytes:root.pub_key length:sizeof(root.pub_key)];
    NSData *chainCode = [NSData dataWithBytes:root.chain_code length:sizeof(root.chain_code)];
    NSError *error = nil;
    NSData *derived = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                                           chainCode:chainCode
                                                                      derivationPath:@"m/0/1"
                                                                               error:&error];
    expect(derived != nil,
           [NSString stringWithFormat:@"wallet public derivation failed: %@", error]);
    NSData *expected = [NSData dataWithBytes:child.pub_key length:sizeof(child.pub_key)];
    expect([derived isEqualToData:expected],
           @"wallet public derivation did not match libwally");
}

static void testWalletPublicKeyDerivationRejectsHardenedPath(void) {
    NSData *rootPublicKey = compressedPublicKeyForSecret(scalarData(1));
    NSData *chainCode = dataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );

    NSError *error = nil;
    NSData *derived = [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                                           chainCode:chainCode
                                                                      derivationPath:@"m/84h/0/0"
                                                                               error:&error];
    expect(derived == nil, @"hardened public derivation unexpectedly succeeded");
    expect([error.domain isEqualToString:WalletPublicKeyDerivationErrorDomain],
           @"hardened public derivation returned wrong error domain");
    expect(error.code == WalletPublicKeyDerivationErrorUnsupportedHardenedPath,
           @"hardened public derivation returned wrong error code");
}

static void testWalletAddressDerivationMatchesAddressHelpers(void) {
    NSData *seed = dataFromHex(@"000102030405060708090a0b0c0d0e0f");

    struct ext_key root;
    memset(&root, 0, sizeof(root));
    int ret = bip32_key_from_seed(seed.bytes, seed.length,
                                  BIP32_VER_MAIN_PRIVATE, 0, &root);
    expect(ret == WALLY_OK, @"BIP32 test root derivation failed");

    NSData *rootPublicKey = [NSData dataWithBytes:root.pub_key length:sizeof(root.pub_key)];
    NSData *chainCode = [NSData dataWithBytes:root.chain_code length:sizeof(root.chain_code)];

    NSError *error = nil;
    NSData *derivedPublicKey =
        [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:rootPublicKey
                                                             chainCode:chainCode
                                                        derivationPath:@"m/0/1"
                                                                 error:&error];
    expect(derivedPublicKey != nil,
           [NSString stringWithFormat:@"wallet public derivation failed: %@", error]);

    NSString *bitcoinAddress =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m/0/1"
                                                       addressType:WalletAddressTypeBitcoinP2WPKHTestnet
                                                             error:&error];
    expect([bitcoinAddress isEqualToString:p2wpkhAddress(derivedPublicKey, NO)],
           @"wallet Bitcoin address derivation did not match helper output");

    NSString *ethAddress =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m/0/1"
                                                       addressType:WalletAddressTypeEthereum
                                                             error:&error];
    expect([ethAddress isEqualToString:ethereumAddress(derivedPublicKey)],
           @"wallet Ethereum address derivation did not match helper output");
}

static void testWalletAddressDerivationRejectsUnsupportedType(void) {
    NSData *rootPublicKey = compressedPublicKeyForSecret(scalarData(1));
    NSData *chainCode = dataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );

    NSError *error = nil;
    NSString *address =
        [WalletAddressDerivation addressForRootCompressedPublicKey:rootPublicKey
                                                         chainCode:chainCode
                                                    derivationPath:@"m"
                                                       addressType:(WalletAddressType)999
                                                             error:&error];
    expect(address == nil, @"unsupported address type unexpectedly succeeded");
    expect([error.domain isEqualToString:WalletAddressDerivationErrorDomain],
           @"unsupported address type returned wrong error domain");
    expect(error.code == WalletAddressDerivationErrorUnsupportedAddressType,
           @"unsupported address type returned wrong error code");
}

static void testWalletShareEnvelopePersistenceRoundTrip(void) {
    NSData *envelopeA = [NSData dataWithBytes:"wrapped-a" length:9];
    NSData *envelopeB = [NSData dataWithBytes:"wrapped-b" length:9];
    NSData *jointPublicKey = compressedPublicKeyForSecret(scalarData(1));
    NSData *chainCode = dataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );

    WalletShareEnvelope *envelope =
        [[WalletShareEnvelope alloc] initWithEnvelopeA:envelopeA
                                            envelopeB:envelopeB
                             jointCompressedPublicKey:jointPublicKey
                                            chainCode:chainCode];
    NSURL *url = temporaryTestFileURL(@"wallet-share-envelope.plist");

    NSError *error = nil;
    expect([envelope writeToURL:url error:&error],
           [NSString stringWithFormat:@"wallet envelope write failed: %@", error]);

    WalletShareEnvelope *loaded = [WalletShareEnvelope loadFromURL:url error:&error];
    expect(loaded != nil,
           [NSString stringWithFormat:@"wallet envelope load failed: %@", error]);
    expect([loaded.envelopeA isEqualToData:envelopeA],
           @"loaded wallet envelope A did not match");
    expect([loaded.envelopeB isEqualToData:envelopeB],
           @"loaded wallet envelope B did not match");
    expect([loaded.jointCompressedPublicKey isEqualToData:jointPublicKey],
           @"loaded wallet public key did not match");
    expect([loaded.chainCode isEqualToData:chainCode],
           @"loaded wallet chain code did not match");

    NSDictionary<NSFileAttributeKey, id> *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:&error];
    expect(attributes != nil,
           [NSString stringWithFormat:@"could not read wallet envelope attributes: %@", error]);
    NSNumber *permissions = attributes[NSFilePosixPermissions];
    expect((permissions.unsignedShortValue & 0777) == 0600,
           @"wallet envelope file should be owner-readable only");
}

static void testWalletShareEnvelopeRejectsInvalidPersistence(void) {
    NSDictionary<NSString *, id> *propertyList = @{
        @"version": @1,
        @"envelopeA": [NSData dataWithBytes:"wrapped-a" length:9],
        @"envelopeB": [NSData dataWithBytes:"wrapped-b" length:9],
        @"jointCompressedPublicKey": [NSData dataWithBytes:"bad" length:3],
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    expect(data != nil,
           [NSString stringWithFormat:@"test plist serialization failed: %@", error]);

    NSURL *url = temporaryTestFileURL(@"invalid-wallet-share-envelope.plist");
    expect([[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:&error],
           [NSString stringWithFormat:@"test directory creation failed: %@", error]);
    expect([data writeToURL:url options:NSDataWritingAtomic error:&error],
           [NSString stringWithFormat:@"test plist write failed: %@", error]);

    WalletShareEnvelope *loaded = [WalletShareEnvelope loadFromURL:url error:&error];
    expect(loaded == nil, @"invalid wallet envelope unexpectedly loaded");
    expect([error.domain isEqualToString:WalletShareEnvelopeErrorDomain],
           @"invalid wallet envelope returned wrong error domain");
    expect(error.code == WalletShareEnvelopeErrorInvalidPersistentEnvelope,
           @"invalid wallet envelope returned wrong error code");
}

static void testSigningBoundaryHeaders(void) {
    macwlt_wallet_t *wallet = NULL;
    macwlt_err_t err = MACWLT_OK;
    expect(wallet == NULL, @"opaque wallet handle should compile as an incomplete type");
    expect(err == MACWLT_OK, @"C ABI error enum should expose MACWLT_OK");
    expect(MACWLT_FAILURE < MACWLT_SUCCESS, @"C ABI should use int status returns");
    expect(@protocol(SigningServiceProtocol) != nil,
           @"SigningServiceProtocol should be visible to Objective-C callers");
    expect(SigningServiceErrorDomain.length > 0,
           @"SigningService should expose its error domain");
    expect(WalletShareEnvelopeErrorDomain.length > 0,
           @"WalletShareEnvelope should expose its error domain");
}

static void testSigningServiceClientDefaultConfiguration(void) {
    expect([SigningServiceClientDefaultServiceName isEqualToString:@"com.macwlt.SigningService"],
           @"SigningServiceClient default service name changed unexpectedly");

    SigningServiceClient *client = [SigningServiceClient clientWithDefaultService];
    expect([client.serviceName isEqualToString:SigningServiceClientDefaultServiceName],
           @"SigningServiceClient did not use the default service name");
    [client invalidate];
}

static void testSigningServiceListenerDelegateExportsService(void) {
    NSError *initError = nil;
    SigningService *service = [[SigningService alloc] initWithError:&initError];
    expect(service != nil,
           [NSString stringWithFormat:@"SigningService init failed: %@", initError]);

    SigningServiceListenerDelegate *delegate =
        [[SigningServiceListenerDelegate alloc] initWithService:service];
    MockXPCConnection *connection = [MockXPCConnection new];
    NSObject *listener = [NSObject new];

    BOOL accepted = [delegate listener:(NSXPCListener *)listener
             shouldAcceptNewConnection:(NSXPCConnection *)connection];
    expect(accepted, @"SigningServiceListenerDelegate rejected a connection");
    expect(connection.exportedInterface != nil,
           @"SigningServiceListenerDelegate did not install an exported interface");
    expect([connection.exportedObject isEqual:service],
           @"SigningServiceListenerDelegate exported the wrong object");
    expect(connection.resumed,
           @"SigningServiceListenerDelegate did not resume the connection");
}

static void testSigningServiceUnsupportedSigning(void) {
    NSError *initError = nil;
    SigningService *service = [[SigningService alloc] initWithError:&initError];
    expect(service != nil,
           [NSString stringWithFormat:@"SigningService init failed: %@", initError]);

    __block NSError *psbtError = nil;
    __block BOOL psbtReplied = NO;
    [service signPSBT:[NSData dataWithBytes:"x" length:1]
            withReply:^(NSData *signedPSBT, NSError *error) {
        psbtReplied = YES;
        expect(signedPSBT == nil, @"unsupported PSBT signing returned data");
        psbtError = error;
    }];
    expect(psbtReplied, @"PSBT signing did not reply synchronously");
    expect([psbtError.domain isEqualToString:SigningServiceErrorDomain],
           @"unsupported PSBT signing returned wrong error domain");
    expect(psbtError.code == MACWLT_ERR_UNAVAILABLE,
           @"PSBT signing before bootstrap returned wrong error code");

    __block NSError *ethError = nil;
    __block BOOL ethReplied = NO;
    [service signEthTx:[NSData dataWithBytes:"x" length:1]
             withReply:^(NSData *signature, NSError *error) {
        ethReplied = YES;
        expect(signature == nil, @"unsupported ETH signing returned data");
        ethError = error;
    }];
    expect(ethReplied, @"ETH signing did not reply synchronously");
    expect([ethError.domain isEqualToString:SigningServiceErrorDomain],
           @"unsupported ETH signing returned wrong error domain");
    expect(ethError.code == MACWLT_ERR_UNAVAILABLE,
           @"ETH signing before bootstrap returned wrong error code");
}

static void testSigningServicePubkeyErrors(void) {
    NSError *initError = nil;
    SigningService *service = [[SigningService alloc] initWithError:&initError];
    expect(service != nil,
           [NSString stringWithFormat:@"SigningService init failed: %@", initError]);

    __block NSError *childError = nil;
    __block BOOL childReplied = NO;
    [service exportPubkeyForDerivationPath:@"m/84h/0h/0h/0/0"
                                 withReply:^(NSData *publicKey, NSError *error) {
        childReplied = YES;
        expect(publicKey == nil, @"unsupported child pubkey export returned data");
        childError = error;
    }];
    expect(childReplied, @"child pubkey export did not reply synchronously");
    expect([childError.domain isEqualToString:SigningServiceErrorDomain],
           @"unsupported child pubkey export returned wrong error domain");
    expect(childError.code == MACWLT_ERR_UNSUPPORTED,
           @"unsupported child pubkey export returned wrong error code");

    __block NSError *rootError = nil;
    __block BOOL rootReplied = NO;
    [service exportPubkeyForDerivationPath:@"m"
                                 withReply:^(NSData *publicKey, NSError *error) {
        rootReplied = YES;
        expect(publicKey == nil, @"root pubkey export before bootstrap returned data");
        rootError = error;
    }];
    expect(rootReplied, @"root pubkey export did not reply synchronously");
    expect([rootError.domain isEqualToString:SigningServiceErrorDomain],
           @"root pubkey export before bootstrap returned wrong error domain");
    expect(rootError.code == MACWLT_ERR_UNAVAILABLE,
           @"root pubkey export before bootstrap returned wrong error code");
}

static void testMacwltCABIWalletLifecycle(void) {
    macwlt_wallet_t *wallet = NULL;
    expect(macwlt_wallet_create(&wallet) == MACWLT_SUCCESS,
           @"macwlt_wallet_create failed");
    expect(wallet != NULL, @"macwlt_wallet_create returned a null wallet");
    expect(macwlt_last_error(wallet) == MACWLT_OK,
           @"new wallet should start with MACWLT_OK");
    expect(strcmp(macwlt_last_error_message(wallet), "ok") == 0,
           @"new wallet should expose an ok error message");
    macwlt_wallet_free(wallet);
    macwlt_wallet_free(NULL);
}

static void testMacwltCABIInvalidArguments(void) {
    expect(macwlt_wallet_create(NULL) == MACWLT_FAILURE,
           @"macwlt_wallet_create unexpectedly accepted null out pointer");
    expect(macwlt_last_error(NULL) == MACWLT_ERR_INVALID_ARGUMENT,
           @"macwlt_last_error should reject null wallet");
    expect(strcmp(macwlt_last_error_message(NULL), "invalid argument") == 0,
           @"macwlt_last_error_message should reject null wallet");
    expect(macwlt_bootstrap_wallet(NULL, NULL, NULL) == MACWLT_FAILURE,
           @"macwlt_bootstrap_wallet unexpectedly accepted null wallet");
}

static void testMacwltCABIBootstrapBufferSizing(void) {
    macwlt_wallet_t *wallet = NULL;
    expect(macwlt_wallet_create(&wallet) == MACWLT_SUCCESS,
           @"macwlt_wallet_create failed");

    uint8_t pubkey[1] = {0};
    size_t pubkeyLength = sizeof(pubkey);
    expect(macwlt_bootstrap_wallet(wallet, pubkey, &pubkeyLength) == MACWLT_FAILURE,
           @"macwlt_bootstrap_wallet unexpectedly accepted undersized output buffer");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_BUFFER_TOO_SMALL,
           @"undersized bootstrap buffer should set MACWLT_ERR_BUFFER_TOO_SMALL");
    expect(pubkeyLength == 33,
           @"bootstrap should report required compressed public key length");

    macwlt_wallet_free(wallet);
}

static void testMacwltCABIUnsupportedOperations(void) {
    macwlt_wallet_t *wallet = NULL;
    expect(macwlt_wallet_create(&wallet) == MACWLT_SUCCESS,
           @"macwlt_wallet_create failed");

    uint8_t oneByte = 0;
    size_t oneByteLength = sizeof(oneByte);
    expect(macwlt_sign_psbt(wallet, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_sign_psbt unexpectedly succeeded before bootstrap");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNAVAILABLE,
           @"macwlt_sign_psbt should report unavailable before bootstrap");

    expect(macwlt_sign_eth_tx(wallet, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_sign_eth_tx unexpectedly succeeded before bootstrap");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNAVAILABLE,
           @"macwlt_sign_eth_tx should report unavailable before bootstrap");

    expect(macwlt_export_pubkey(wallet, "m/84h/0h/0h/0/0", &oneByte, &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_export_pubkey unexpectedly accepted child derivation before derivation implementation");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNSUPPORTED,
           @"macwlt_export_pubkey child path should report unsupported");

    expect(macwlt_export_attestation(wallet, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_export_attestation unexpectedly succeeded before attestation implementation");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNSUPPORTED,
           @"macwlt_export_attestation should report unsupported");

    oneByteLength = sizeof(oneByte);
    expect(macwlt_export_address(wallet, "m", (macwlt_address_type_t)999, (char *)&oneByte, &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_export_address unexpectedly accepted unsupported address type");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNSUPPORTED,
           @"unsupported address type should report unsupported");

    oneByteLength = sizeof(oneByte);
    expect(macwlt_export_address(wallet, "m/84h/0/0",
                                 MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET,
                                 (char *)&oneByte,
                                 &oneByteLength) == MACWLT_FAILURE,
           @"macwlt_export_address unexpectedly accepted hardened public derivation");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNSUPPORTED,
           @"hardened address derivation should report unsupported");

    macwlt_wallet_free(wallet);
}

static void testMacwltCABIRootPubkeyExportStateAndSizing(void) {
    macwlt_wallet_t *wallet = NULL;
    expect(macwlt_wallet_create(&wallet) == MACWLT_SUCCESS,
           @"macwlt_wallet_create failed");

    uint8_t pubkey[1] = {0};
    size_t pubkeyLength = sizeof(pubkey);
    expect(macwlt_export_pubkey(wallet, "m", pubkey, &pubkeyLength) == MACWLT_FAILURE,
           @"macwlt_export_pubkey unexpectedly accepted undersized root pubkey buffer");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_BUFFER_TOO_SMALL,
           @"undersized root pubkey buffer should set MACWLT_ERR_BUFFER_TOO_SMALL");
    expect(pubkeyLength == 33,
           @"root pubkey export should report required compressed public key length");

    uint8_t fullPubkey[33] = {0};
    pubkeyLength = sizeof(fullPubkey);
    expect(macwlt_export_pubkey(wallet, "m", fullPubkey, &pubkeyLength) == MACWLT_FAILURE,
           @"macwlt_export_pubkey unexpectedly succeeded before bootstrap");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNAVAILABLE,
           @"root pubkey export before bootstrap should report unavailable");

    expect(macwlt_export_pubkey(wallet, NULL, fullPubkey, &pubkeyLength) == MACWLT_FAILURE,
           @"macwlt_export_pubkey unexpectedly accepted null derivation path");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_INVALID_ARGUMENT,
           @"null derivation path should report invalid argument");

    char address[64] = {0};
    size_t addressLength = sizeof(address);
    expect(macwlt_export_address(wallet, "m",
                                 MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET,
                                 address,
                                 &addressLength) == MACWLT_FAILURE,
           @"macwlt_export_address unexpectedly succeeded before bootstrap");
    expect(macwlt_last_error(wallet) == MACWLT_ERR_UNAVAILABLE,
           @"address export before bootstrap should report unavailable");

    macwlt_wallet_free(wallet);
}

int main(void) {
    @autoreleasepool {
        expect(wally_init(0) == WALLY_OK, @"wally_init failed");
        testHex();
        testBIP39MnemonicSeed();
        testP2WPKHAddress();
        testEthereumAddress();
        testPSBTInvalidData();
        testHardenedBufferMasksMemory();
        testHardenedBufferWipeAndMask();
        testHardenedShareWindowSequencing();
        testHardenedShareWindowMasksAfterFailure();
        testHardenedShareWindowRejectsClosedLoader();
        testSigningShareSetKnownPublicKey();
        testSigningShareSetRejectsInvalidShare();
        testSigningShareSetGeneratedCommutative();
        testWalletSignerSignsWithSplitShares();
        testWalletPublicKeyDerivationMatchesWally();
        testWalletPublicKeyDerivationRejectsHardenedPath();
        testWalletAddressDerivationMatchesAddressHelpers();
        testWalletAddressDerivationRejectsUnsupportedType();
        testWalletShareEnvelopePersistenceRoundTrip();
        testWalletShareEnvelopeRejectsInvalidPersistence();
        testSigningBoundaryHeaders();
        testSigningServiceClientDefaultConfiguration();
        testSigningServiceListenerDelegateExportsService();
        testMacwltCABIWalletLifecycle();
        testMacwltCABIInvalidArguments();
        testMacwltCABIBootstrapBufferSizing();
        testMacwltCABIUnsupportedOperations();
        testMacwltCABIRootPubkeyExportStateAndSizing();
        testSigningServiceUnsupportedSigning();
        testSigningServicePubkeyErrors();
        NSLog(@"core tests passed");
    }
    return 0;
}
