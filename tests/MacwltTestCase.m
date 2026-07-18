/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#include <secp256k1.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wally_core.h>
#include <wally_crypto.h>

@implementation MacwltTestCase

- (void)setUp {
    [super setUp];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        XCTAssertEqual(wally_init(0), WALLY_OK);
    });
}

@end

NSData *MacwltTestDataFromHex(NSString *string) {
    NSMutableData *data = [NSMutableData dataWithCapacity:string.length / 2];
    for (NSUInteger i = 0; i + 1 < string.length; i += 2) {
        NSString *byteString = [string substringWithRange:NSMakeRange(i, 2)];
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:byteString];
        XCTAssertTrue([scanner scanHexInt:&byte], @"invalid hex byte %@", byteString);
        uint8_t value = (uint8_t)byte;
        [data appendBytes:&value length:sizeof(value)];
    }
    return data;
}

NSData *MacwltTestScalarData(uint8_t value) {
    NSMutableData *data = [NSMutableData dataWithLength:32];
    uint8_t *bytes = data.mutableBytes;
    bytes[31] = value;
    return data;
}

NSData *MacwltTestCompressedPublicKeyForSecret(NSData *secret) {
    secp256k1_context *ctx = wally_get_secp_context();
    XCTAssertNotEqual(ctx, NULL, @"secp256k1 context unavailable");

    secp256k1_pubkey pubkey;
    XCTAssertTrue(secp256k1_ec_pubkey_create(ctx, &pubkey, secret.bytes),
                  @"secp256k1_ec_pubkey_create failed");

    uint8_t compressed[33];
    size_t compressedLength = sizeof(compressed);
    XCTAssertTrue(secp256k1_ec_pubkey_serialize(ctx,
                                                compressed,
                                                &compressedLength,
                                                &pubkey,
                                                SECP256K1_EC_COMPRESSED),
                  @"secp256k1_ec_pubkey_serialize failed");
    XCTAssertEqual(compressedLength, sizeof(compressed),
                   @"unexpected compressed public key length");
    return [NSData dataWithBytes:compressed length:sizeof(compressed)];
}

NSData *MacwltTestPrivateKeyByMultiplying(NSData *a, NSData *b) {
    NSMutableData *out = [NSMutableData dataWithLength:32];
    XCTAssertEqual(wally_ec_scalar_multiply(a.bytes, a.length,
                                            b.bytes, b.length,
                                            out.mutableBytes, out.length),
                   WALLY_OK,
                   @"test scalar multiply failed");
    return out;
}

NSData *MacwltTestPrivateKeyByAdding(NSData *a, NSData *b) {
    NSMutableData *out = [NSMutableData dataWithLength:32];
    XCTAssertEqual(wally_ec_scalar_add(a.bytes, a.length,
                                       b.bytes, b.length,
                                       out.mutableBytes, out.length),
                   WALLY_OK,
                   @"test scalar add failed");
    return out;
}

NSURL *MacwltTestTemporaryFileURL(NSString *name) {
    NSString *directory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    return [[NSURL fileURLWithPath:directory isDirectory:YES]
        URLByAppendingPathComponent:name
                        isDirectory:NO];
}

static sigjmp_buf MacwltTestMaskedReadJump;
static volatile sig_atomic_t MacwltTestExpectingMaskedReadSignal = 0;

static void MacwltTestMaskedReadSignalHandler(int signalNumber) {
    if (MacwltTestExpectingMaskedReadSignal) siglongjmp(MacwltTestMaskedReadJump, signalNumber);
    _exit(128 + signalNumber);
}

BOOL MacwltTestReadTriggersProtectionFault(volatile uint8_t *address) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = MacwltTestMaskedReadSignalHandler;
    sigemptyset(&action.sa_mask);

    struct sigaction previousSEGV;
    struct sigaction previousBUS;
    sigaction(SIGSEGV, &action, &previousSEGV);
    sigaction(SIGBUS, &action, &previousBUS);

    int signalNumber = sigsetjmp(MacwltTestMaskedReadJump, 1);
    if (signalNumber == 0) {
        MacwltTestExpectingMaskedReadSignal = 1;
        volatile uint8_t value = *address;
        (void)value;
        MacwltTestExpectingMaskedReadSignal = 0;
        sigaction(SIGSEGV, &previousSEGV, NULL);
        sigaction(SIGBUS, &previousBUS, NULL);
        return NO;
    }

    MacwltTestExpectingMaskedReadSignal = 0;
    sigaction(SIGSEGV, &previousSEGV, NULL);
    sigaction(SIGBUS, &previousBUS, NULL);
    return signalNumber == SIGSEGV || signalNumber == SIGBUS;
}

BOOL MacwltTestWalletResetTestsEnabled(void) {
    const char *value = getenv("MACWLT_RUN_WALLET_RESET_TESTS");
    return value && strcmp(value, "1") == 0;
}
