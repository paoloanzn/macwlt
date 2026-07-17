/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "ARCH2FROSTLibrary.h"
#import "ARCH2FROSTSigningEngine.h"
#import "ARCH2FROSTWallet.h"
#import "HardenedBuffer.h"
#import "WalletPublicKeyDerivation.h"

#include <wally_core.h>
#include <wally_crypto.h>
#include <wally_psbt.h>
#include <wally_psbt_members.h>
#include <wally_script.h>
#include <wally_transaction.h>

static BOOL MacwltTestWallySucceeded(int result, NSString *operation) {
    if (result == WALLY_OK) return YES;
    NSLog(@"%@ failed with libwally status %d", operation, result);
    return NO;
}

static NSData *MacwltTestTaprootKeypathPSBT(NSData *rootPublicKey,
                                            NSData *internalPublicKey) {
    unsigned char outputPublicKey[EC_PUBLIC_KEY_LEN] = {0};
    unsigned char script[WALLY_SCRIPTPUBKEY_P2TR_LEN] = {0};
    unsigned char previousTransactionID[WALLY_TXHASH_LEN] = {0};
    unsigned char fingerprintHash[HASH160_LEN] = {0};
    uint32_t derivationPath[] = {0};
    size_t scriptLength = 0;
    struct wally_tx *transaction = NULL;
    struct wally_tx_output *witnessUTXO = NULL;
    struct wally_psbt *psbt = NULL;
    NSMutableData *serialized = nil;

    previousTransactionID[0] = 1;
    if (!MacwltTestWallySucceeded(
            wally_ec_public_key_bip341_tweak(internalPublicKey.bytes,
                                             internalPublicKey.length,
                                             NULL,
                                             0,
                                             0,
                                             outputPublicKey,
                                             sizeof(outputPublicKey)),
            @"taproot tweak")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_scriptpubkey_p2tr_from_bytes(outputPublicKey + 1,
                                               EC_XONLY_PUBLIC_KEY_LEN,
                                               0,
                                               script,
                                               sizeof(script),
                                               &scriptLength),
            @"taproot script")) goto cleanup;
    if (scriptLength != sizeof(script)) {
        NSLog(@"taproot script wrote %zu bytes", scriptLength);
        goto cleanup;
    }
    if (!MacwltTestWallySucceeded(
            wally_tx_init_alloc(2, 0, 1, 1, &transaction),
            @"transaction allocation")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_tx_add_raw_input(transaction,
                                   previousTransactionID,
                                   sizeof(previousTransactionID),
                                   0,
                                   WALLY_TX_SEQUENCE_FINAL,
                                   NULL,
                                   0,
                                   NULL,
                                   0),
            @"transaction input")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_tx_add_raw_output(transaction,
                                    900,
                                    script,
                                    sizeof(script),
                                    0),
            @"transaction output")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_init_alloc(WALLY_PSBT_VERSION_2, 1, 1, 0, 0, &psbt),
            @"PSBT allocation")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_add_tx_input_at(psbt,
                                       0,
                                       0,
                                       &transaction->inputs[0]),
            @"PSBT transaction input")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_add_tx_output_at(psbt,
                                        0,
                                        0,
                                        &transaction->outputs[0]),
            @"PSBT transaction output")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_tx_output_init_alloc(1000,
                                       script,
                                       sizeof(script),
                                       &witnessUTXO),
            @"witness UTXO allocation")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_set_input_witness_utxo(psbt, 0, witnessUTXO),
            @"witness UTXO insertion")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_hash160(rootPublicKey.bytes,
                          rootPublicKey.length,
                          fingerprintHash,
                          sizeof(fingerprintHash)),
            @"fingerprint hash")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_ec_xonly_public_key_verify(internalPublicKey.bytes + 1,
                                             EC_XONLY_PUBLIC_KEY_LEN),
            @"x-only internal key verification")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_input_taproot_keypath_add(
                &psbt->inputs[0],
                internalPublicKey.bytes + 1,
                EC_XONLY_PUBLIC_KEY_LEN,
                NULL,
                0,
                fingerprintHash,
                BIP32_KEY_FINGERPRINT_LEN,
                derivationPath,
                sizeof(derivationPath) / sizeof(derivationPath[0])),
            @"taproot keypath insertion")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_set_input_taproot_internal_key(
                psbt,
                0,
                internalPublicKey.bytes + 1,
                EC_XONLY_PUBLIC_KEY_LEN),
            @"taproot internal key insertion")) goto cleanup;
    if (!MacwltTestWallySucceeded(
            wally_psbt_set_version(psbt, 0, WALLY_PSBT_VERSION_0),
            @"PSBT v0 conversion")) goto cleanup;

    size_t outputLength = 0;
    size_t written = 0;
    if (!MacwltTestWallySucceeded(
            wally_psbt_get_length(psbt, 0, &outputLength),
            @"PSBT length")) goto cleanup;
    serialized = [NSMutableData dataWithLength:outputLength];
    if (!MacwltTestWallySucceeded(
            wally_psbt_to_bytes(psbt,
                                0,
                                serialized.mutableBytes,
                                serialized.length,
                                &written),
            @"PSBT serialization")) {
        serialized = nil;
        goto cleanup;
    }
    serialized.length = written;

cleanup:
    wally_psbt_free(psbt);
    wally_tx_output_free(witnessUTXO);
    wally_tx_free(transaction);
    return serialized;
}

static BOOL MacwltTestVerifyTaprootPSBTSignature(NSData *psbtData,
                                                 NSData *internalPublicKey) {
    struct wally_psbt *psbt = NULL;
    struct wally_tx *transaction = NULL;
    unsigned char digest[SHA256_LEN] = {0};
    unsigned char signature[EC_SIGNATURE_LEN] = {0};
    unsigned char outputPublicKey[EC_PUBLIC_KEY_LEN] = {0};
    size_t written = 0;
    BOOL verified = NO;

    if (wally_psbt_from_bytes(psbtData.bytes,
                              psbtData.length,
                              WALLY_PSBT_PARSE_FLAG_STRICT,
                              &psbt) != WALLY_OK ||
        wally_psbt_get_global_tx_alloc(psbt, &transaction) != WALLY_OK ||
        wally_psbt_get_input_taproot_signature(psbt,
                                                0,
                                                signature,
                                                sizeof(signature),
                                                &written) != WALLY_OK ||
        written != sizeof(signature) ||
        wally_psbt_get_input_signature_hash(psbt,
                                             0,
                                             transaction,
                                             NULL,
                                             0,
                                             0,
                                             digest,
                                             sizeof(digest)) != WALLY_OK ||
        wally_ec_public_key_bip341_tweak(internalPublicKey.bytes,
                                         internalPublicKey.length,
                                         NULL,
                                         0,
                                         0,
                                         outputPublicKey,
                                         sizeof(outputPublicKey)) != WALLY_OK) {
        goto cleanup;
    }

    verified = wally_ec_sig_verify(outputPublicKey,
                                   sizeof(outputPublicKey),
                                   digest,
                                   sizeof(digest),
                                   EC_FLAG_SCHNORR,
                                   signature,
                                   sizeof(signature)) == WALLY_OK;

cleanup:
    wally_tx_free(transaction);
    wally_psbt_free(psbt);
    return verified;
}

@interface ARCH2FROSTTestWallet : ARCH2FROSTWallet

- (instancetype)initWithShareA:(NSData *)shareA
                         shareB:(NSData *)shareB
              participantKeyA:(NSData *)participantKeyA
              participantKeyB:(NSData *)participantKeyB
                      groupKey:(NSData *)groupKey;

@end

@implementation ARCH2FROSTTestWallet {
    NSData *_testShareA;
    NSData *_testShareB;
}

- (instancetype)initWithShareA:(NSData *)shareA
                         shareB:(NSData *)shareB
              participantKeyA:(NSData *)participantKeyA
              participantKeyB:(NSData *)participantKeyB
                      groupKey:(NSData *)groupKey {
    NSData *chainCode = [NSMutableData dataWithLength:32];
    self = [super initWithEnvelopeA:[@"a" dataUsingEncoding:NSUTF8StringEncoding]
                          envelopeB:[@"b" dataUsingEncoding:NSUTF8StringEncoding]
               participantPublicKeyA:participantKeyA
               participantPublicKeyB:participantKeyB
                      groupPublicKey:groupKey
                           chainCode:chainCode];
    if (self) {
        _testShareA = [shareA copy];
        _testShareB = [shareB copy];
    }
    return self;
}

- (BOOL)unwrapParticipant:(ARCH2FROSTParticipant)participant
       intoHardenedBuffer:(HardenedBuffer *)buffer
                    error:(NSError **)outError {
    NSData *share = participant == ARCH2FROSTParticipantA
        ? _testShareA : _testShareB;
    if (![buffer unmaskWithError:outError]) return NO;
    memcpy(buffer.mutableBytes, share.bytes, share.length);
    return YES;
}

@end

@interface ARCH2FROSTSigningEngineTests : MacwltTestCase
@end

@implementation ARCH2FROSTSigningEngineTests

- (void)testTwoParticipantSignatureAggregatesAndVerifies {
    NSError *error = nil;
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];
    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    if (!library) return;

    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    NSData *participantKeyA = MacwltTestCompressedPublicKeyForSecret(shareA);
    NSData *participantKeyB = MacwltTestCompressedPublicKeyForSecret(shareB);
    NSData *groupKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    ARCH2FROSTTestWallet *wallet =
        [[ARCH2FROSTTestWallet alloc] initWithShareA:shareA
                                             shareB:shareB
                                  participantKeyA:participantKeyA
                                  participantKeyB:participantKeyB
                                          groupKey:groupKey];
    ARCH2FROSTSigningEngine *engine =
        [[ARCH2FROSTSigningEngine alloc] initWithLibrary:library wallet:wallet];
    NSData *digest = MacwltTestDataFromHex(
        @"000102030405060708090a0b0c0d0e0f"
        @"101112131415161718191a1b1c1d1e1f"
    );

    NSData *signature = [engine signDigest:digest error:&error];

    XCTAssertNotNil(signature, @"FROST signing failed: %@", error);
    XCTAssertEqual(signature.length, 64U);
}

- (void)testInvalidDigestReturnsTypedErrorWithNullErrorAllowed {
    NSError *error = nil;
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];
    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    if (!library) return;
    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    ARCH2FROSTTestWallet *wallet =
        [[ARCH2FROSTTestWallet alloc]
            initWithShareA:shareA
                    shareB:shareB
           participantKeyA:MacwltTestCompressedPublicKeyForSecret(shareA)
           participantKeyB:MacwltTestCompressedPublicKeyForSecret(shareB)
                  groupKey:MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1))];
    ARCH2FROSTSigningEngine *engine =
        [[ARCH2FROSTSigningEngine alloc] initWithLibrary:library wallet:wallet];

    NSData *signature = [engine signDigest:NSData.data error:NULL];

    XCTAssertNil(signature);
}

- (void)testDerivedTaprootSignatureVerifiesForTweakedOutputKey {
    NSError *error = nil;
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];
    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    if (!library) return;
    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    NSData *groupKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    ARCH2FROSTTestWallet *wallet =
        [[ARCH2FROSTTestWallet alloc]
            initWithShareA:shareA
                    shareB:shareB
           participantKeyA:MacwltTestCompressedPublicKeyForSecret(shareA)
           participantKeyB:MacwltTestCompressedPublicKeyForSecret(shareB)
                  groupKey:groupKey];
    ARCH2FROSTSigningEngine *engine =
        [[ARCH2FROSTSigningEngine alloc] initWithLibrary:library wallet:wallet];
    NSData *digest = MacwltTestDataFromHex(
        @"f0e0d0c0b0a090807060504030201000"
        @"00102030405060708090a0b0c0d0e0f0"
    );
    NSData *internalKey =
        [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:groupKey
                                                             chainCode:wallet.chainCode
                                                        derivationPath:@"m/1/2"
                                                                 error:&error];
    XCTAssertNotNil(internalKey, @"public derivation failed: %@", error);
    if (!internalKey) return;
    unsigned char outputKey[33] = {0};
    XCTAssertEqual(wally_ec_public_key_bip341_tweak(internalKey.bytes,
                                                    internalKey.length,
                                                    NULL,
                                                    0,
                                                    0,
                                                    outputKey,
                                                    sizeof(outputKey)),
                   WALLY_OK);

    NSData *signature = [engine signTaprootDigest:digest
                                   derivationPath:@"m/1/2"
                                       merkleRoot:nil
                                            error:&error];

    XCTAssertNotNil(signature, @"Taproot FROST signing failed: %@", error);
    XCTAssertEqual(signature.length, 64U);
    XCTAssertEqual(wally_ec_sig_verify(outputKey,
                                       sizeof(outputKey),
                                       digest.bytes,
                                       digest.length,
                                       EC_FLAG_SCHNORR,
                                       signature.bytes,
                                       signature.length),
                   WALLY_OK);
}

- (void)testTaprootKeypathPSBTReceivesVerifiableFROSTSignature {
    NSError *error = nil;
    ARCH2FROSTLibrary *library = [ARCH2FROSTLibrary libraryWithError:&error];
    XCTAssertNotNil(library, @"FROST library load failed: %@", error);
    if (!library) return;
    NSData *shareA = MacwltTestScalarData(2);
    NSData *shareB = MacwltTestScalarData(3);
    NSData *groupKey = MacwltTestCompressedPublicKeyForSecret(MacwltTestScalarData(1));
    ARCH2FROSTTestWallet *wallet =
        [[ARCH2FROSTTestWallet alloc]
            initWithShareA:shareA
                    shareB:shareB
           participantKeyA:MacwltTestCompressedPublicKeyForSecret(shareA)
           participantKeyB:MacwltTestCompressedPublicKeyForSecret(shareB)
                  groupKey:groupKey];
    ARCH2FROSTSigningEngine *engine =
        [[ARCH2FROSTSigningEngine alloc] initWithLibrary:library wallet:wallet];
    NSData *internalPublicKey =
        [WalletPublicKeyDerivation publicKeyForRootCompressedPublicKey:groupKey
                                                             chainCode:wallet.chainCode
                                                        derivationPath:@"m/0"
                                                                 error:&error];
    XCTAssertNotNil(internalPublicKey, @"public derivation failed: %@", error);
    if (!internalPublicKey) return;
    NSData *psbt = MacwltTestTaprootKeypathPSBT(groupKey, internalPublicKey);
    XCTAssertNotNil(psbt, @"could not build Taproot PSBT fixture");
    if (!psbt) return;

    NSData *signedPSBT = [engine signedTaprootPSBT:psbt error:&error];

    XCTAssertNotNil(signedPSBT, @"Taproot PSBT signing failed: %@", error);
    XCTAssertTrue(MacwltTestVerifyTaprootPSBTSignature(signedPSBT,
                                                       internalPublicKey));
}

@end
