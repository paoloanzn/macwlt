/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "PSBT.h"

#import <dispatch/dispatch.h>

#include <stdarg.h>
#include <string.h>

#include <wally_core.h>
#include <wally_psbt.h>
#include <wally_psbt_members.h>
#include <wally_transaction.h>

NSString * const PSBTErrorDomain = @"macwlt.PSBT";

static BOOL PSBTFail(NSError **outError, PSBTErrorCode code, NSString *format, ...) {
    if (outError) {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        *outError = [NSError errorWithDomain:PSBTErrorDomain
                                        code:code
                                    userInfo:@{ NSLocalizedDescriptionKey: message }];
    }
    return NO;
}

static BOOL PSBTEnsureWally(NSError **outError) {
    static dispatch_once_t once;
    static int initResult = WALLY_ERROR;
    dispatch_once(&once, ^{
        initResult = wally_init(0);
    });
    if (initResult == WALLY_OK) return YES;
    return PSBTFail(outError, PSBTErrorInvalidPSBT,
                    @"libwally initialization failed with code %d", initResult);
}

static PSBTErrorCode PSBTErrorCodeForWally(int code) {
    return code == WALLY_EINVAL ? PSBTErrorInvalidData : PSBTErrorInvalidPSBT;
}

static BOOL PSBTFailWally(NSError **outError, NSString *operation, int code) {
    return PSBTFail(outError, PSBTErrorCodeForWally(code),
                    @"%@ failed with libwally code %d", operation, code);
}

static NSData *PSBTDataFromTx(const struct wally_tx *tx, NSError **outError) {
    size_t length = 0;
    int ret = wally_tx_get_length(tx, 0, &length);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_tx_get_length", ret);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:length];
    size_t written = 0;
    ret = wally_tx_to_bytes(tx, 0, data.mutableBytes, data.length, &written);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_tx_to_bytes", ret);
        return nil;
    }
    data.length = written;
    return data;
}

static struct wally_tx *PSBTTransactionFromData(NSData *data, NSError **outError) {
    struct wally_tx *tx = NULL;
    int ret = wally_tx_from_bytes(data.bytes, data.length, 0, &tx);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_tx_from_bytes", ret);
        return NULL;
    }
    return tx;
}

@interface PSBT ()

- (nullable instancetype)initWithWallyPSBT:(struct wally_psbt *)psbt;

@end

@implementation PSBT {
    struct wally_psbt *_psbt;
}

- (instancetype)init {
    if (!PSBTEnsureWally(NULL)) return nil;

    struct wally_psbt *psbt = NULL;
    int ret = wally_psbt_init_alloc(WALLY_PSBT_VERSION_0, 0, 0, 0, 0, &psbt);
    if (ret != WALLY_OK) return nil;
    return [self initWithWallyPSBT:psbt];
}

- (nullable instancetype)initWithWallyPSBT:(struct wally_psbt *)psbt {
    self = [super init];
    if (self) {
        _psbt = psbt;
    } else if (psbt) {
        wally_psbt_free(psbt);
    }
    return self;
}

- (void)dealloc {
    if (_psbt) wally_psbt_free(_psbt);
}

+ (nullable instancetype)psbtWithData:(NSData *)data error:(NSError **)outError {
    return [[self alloc] initWithData:data error:outError];
}

+ (nullable instancetype)psbtWithBase64String:(NSString *)base64 error:(NSError **)outError {
    if (!PSBTEnsureWally(outError)) return nil;

    NSArray<NSString *> *parts = [base64 componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalized = [parts componentsJoinedByString:@""];
    NSData *utf8 = [normalized dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) {
        PSBTFail(outError, PSBTErrorInvalidData, @"invalid PSBT base64 string");
        return nil;
    }

    struct wally_psbt *psbt = NULL;
    int ret = wally_psbt_from_base64_n(utf8.bytes, utf8.length,
                                       WALLY_PSBT_PARSE_FLAG_STRICT, &psbt);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_from_base64_n", ret);
        return nil;
    }
    return [[self alloc] initWithWallyPSBT:psbt];
}

+ (nullable instancetype)version0PSBTWithUnsignedTransaction:(NSData *)transaction error:(NSError **)outError {
    if (!PSBTEnsureWally(outError)) return nil;

    struct wally_tx *tx = PSBTTransactionFromData(transaction, outError);
    if (!tx) return nil;

    struct wally_psbt *psbt = NULL;
    int ret = wally_psbt_from_tx(tx, WALLY_PSBT_VERSION_0, 0, &psbt);
    wally_tx_free(tx);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_from_tx", ret);
        return nil;
    }
    return [[self alloc] initWithWallyPSBT:psbt];
}

+ (nullable instancetype)version2PSBTWithInputCount:(NSUInteger)inputCount
                                        outputCount:(NSUInteger)outputCount
                                 transactionVersion:(uint32_t)transactionVersion {
    if (!PSBTEnsureWally(NULL)) return nil;

    struct wally_psbt *psbt = NULL;
    int ret = wally_psbt_init_alloc(WALLY_PSBT_VERSION_2, inputCount, outputCount, 0, 0, &psbt);
    if (ret != WALLY_OK) return nil;

    ret = wally_psbt_set_tx_version(psbt, transactionVersion);
    if (ret != WALLY_OK) {
        wally_psbt_free(psbt);
        return nil;
    }

    uint8_t zeroHash[WALLY_TXHASH_LEN] = {0};
    for (NSUInteger i = 0; i < inputCount; i++) {
        struct wally_tx_input *input = NULL;
        ret = wally_tx_input_init_alloc(zeroHash, sizeof(zeroHash), 0,
                                        WALLY_TX_SEQUENCE_FINAL, NULL, 0, NULL, &input);
        if (ret == WALLY_OK) ret = wally_psbt_add_tx_input_at(psbt, (uint32_t)i, 0, input);
        if (input) wally_tx_input_free(input);
        if (ret != WALLY_OK) {
            wally_psbt_free(psbt);
            return nil;
        }
    }

    for (NSUInteger i = 0; i < outputCount; i++) {
        struct wally_tx_output *output = NULL;
        ret = wally_tx_output_init_alloc(0, NULL, 0, &output);
        if (ret == WALLY_OK) ret = wally_psbt_add_tx_output_at(psbt, (uint32_t)i, 0, output);
        if (output) wally_tx_output_free(output);
        if (ret != WALLY_OK) {
            wally_psbt_free(psbt);
            return nil;
        }
    }

    return [[self alloc] initWithWallyPSBT:psbt];
}

- (nullable instancetype)initWithData:(NSData *)data error:(NSError **)outError {
    if (!PSBTEnsureWally(outError)) return nil;

    struct wally_psbt *psbt = NULL;
    int ret = wally_psbt_from_bytes(data.bytes, data.length,
                                    WALLY_PSBT_PARSE_FLAG_STRICT, &psbt);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_from_bytes", ret);
        return nil;
    }
    return [self initWithWallyPSBT:psbt];
}

- (uint32_t)version {
    size_t version = 0;
    int ret = wally_psbt_get_version(_psbt, &version);
    return ret == WALLY_OK ? (uint32_t)version : 0;
}

- (void)setVersion:(uint32_t)version {
    if (version == WALLY_PSBT_VERSION_0 || version == WALLY_PSBT_VERSION_2) {
        (void)wally_psbt_set_version(_psbt, 0, version);
    }
}

- (NSUInteger)inputCount {
    size_t count = 0;
    int ret = wally_psbt_get_num_inputs(_psbt, &count);
    return ret == WALLY_OK ? count : 0;
}

- (NSUInteger)outputCount {
    size_t count = 0;
    int ret = wally_psbt_get_num_outputs(_psbt, &count);
    return ret == WALLY_OK ? count : 0;
}

- (NSData *)unsignedTransaction {
    struct wally_tx *tx = NULL;
    int ret = wally_psbt_get_global_tx_alloc(_psbt, &tx);
    if (ret != WALLY_OK || !tx) return nil;

    NSData *data = PSBTDataFromTx(tx, NULL);
    wally_tx_free(tx);
    return data;
}

- (void)setUnsignedTransaction:(NSData *)unsignedTransaction {
    if (!unsignedTransaction) return;

    struct wally_tx *tx = PSBTTransactionFromData(unsignedTransaction, NULL);
    if (!tx) return;
    (void)wally_psbt_set_global_tx(_psbt, tx);
    wally_tx_free(tx);
}

- (NSNumber *)transactionVersion {
    size_t txVersion = 0;
    int ret = wally_psbt_get_tx_version(_psbt, &txVersion);
    return ret == WALLY_OK ? @(txVersion) : nil;
}

- (void)setTransactionVersion:(NSNumber *)transactionVersion {
    if (transactionVersion) {
        (void)wally_psbt_set_tx_version(_psbt, transactionVersion.unsignedIntValue);
    }
}

- (NSNumber *)fallbackLocktime {
    size_t hasLocktime = 0;
    int ret = wally_psbt_has_fallback_locktime(_psbt, &hasLocktime);
    if (ret != WALLY_OK || !hasLocktime) return nil;

    size_t locktime = 0;
    ret = wally_psbt_get_fallback_locktime(_psbt, &locktime);
    return ret == WALLY_OK ? @(locktime) : nil;
}

- (void)setFallbackLocktime:(NSNumber *)fallbackLocktime {
    if (fallbackLocktime) {
        (void)wally_psbt_set_fallback_locktime(_psbt, fallbackLocktime.unsignedIntValue);
    } else {
        (void)wally_psbt_clear_fallback_locktime(_psbt);
    }
}

- (NSNumber *)txModifiableFlags {
    size_t flags = 0;
    int ret = wally_psbt_get_tx_modifiable_flags(_psbt, &flags);
    return ret == WALLY_OK ? @(flags) : nil;
}

- (void)setTxModifiableFlags:(NSNumber *)txModifiableFlags {
    (void)wally_psbt_set_tx_modifiable_flags(_psbt, txModifiableFlags ? txModifiableFlags.unsignedIntValue : 0);
}

- (nullable NSData *)serializedDataWithError:(NSError **)outError {
    size_t length = 0;
    int ret = wally_psbt_get_length(_psbt, 0, &length);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_get_length", ret);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:length];
    size_t written = 0;
    ret = wally_psbt_to_bytes(_psbt, 0, data.mutableBytes, data.length, &written);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_to_bytes", ret);
        return nil;
    }
    data.length = written;
    return data;
}

- (nullable NSString *)base64StringWithError:(NSError **)outError {
    char *base64 = NULL;
    int ret = wally_psbt_to_base64(_psbt, 0, &base64);
    if (ret != WALLY_OK) {
        PSBTFailWally(outError, @"wally_psbt_to_base64", ret);
        return nil;
    }

    NSString *string = [NSString stringWithUTF8String:base64];
    wally_free_string(base64);
    return string;
}

@end
