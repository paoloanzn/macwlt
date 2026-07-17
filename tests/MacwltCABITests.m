/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#include "../src/core/macwlt.h"
#include <string.h>

@interface MacwltCABITests : MacwltTestCase
@property (nonatomic) macwlt_wallet_t *sut;
@end

@implementation MacwltCABITests

- (void)tearDown {
    macwlt_wallet_free(self.sut);
    self.sut = NULL;
    [super tearDown];
}

- (void)testWalletLifecycleStartsWithOkErrorState {
    int status = macwlt_wallet_create(&_sut);

    XCTAssertEqual(status, MACWLT_SUCCESS);
    XCTAssertNotEqual(self.sut, NULL);
    XCTAssertEqual(macwlt_last_error(self.sut), MACWLT_OK);
    XCTAssertEqual(strcmp(macwlt_last_error_message(self.sut), "ok"), 0);
    macwlt_wallet_free(NULL);
}

- (void)testInvalidArgumentsReturnFailureAndInvalidArgumentError {
    int createStatus = macwlt_wallet_create(NULL);
    macwlt_err_t lastError = macwlt_last_error(NULL);
    const char *lastMessage = macwlt_last_error_message(NULL);
    int bootstrapStatus = macwlt_bootstrap_wallet(NULL, NULL, NULL);

    XCTAssertEqual(createStatus, MACWLT_FAILURE);
    XCTAssertEqual(lastError, MACWLT_ERR_INVALID_ARGUMENT);
    XCTAssertEqual(strcmp(lastMessage, "invalid argument"), 0);
    XCTAssertEqual(bootstrapStatus, MACWLT_FAILURE);
}

- (void)testBootstrapReportsRequiredPublicKeyBufferSize {
    XCTAssertEqual(macwlt_wallet_create(&_sut), MACWLT_SUCCESS);
    uint8_t pubkey[1] = {0};
    size_t pubkeyLength = sizeof(pubkey);

    int status = macwlt_bootstrap_wallet(self.sut, pubkey, &pubkeyLength);

    XCTAssertEqual(status, MACWLT_FAILURE);
    XCTAssertEqual(macwlt_last_error(self.sut), MACWLT_ERR_BUFFER_TOO_SMALL);
    XCTAssertEqual(pubkeyLength, 33U);
}

- (void)testUnsupportedOperationsBeforeBootstrapReportSpecificErrors {
    XCTAssertEqual(macwlt_wallet_create(&_sut), MACWLT_SUCCESS);
    uint8_t oneByte = 0;
    size_t oneByteLength = sizeof(oneByte);

    int psbtStatus = macwlt_sign_psbt(self.sut, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength);
    macwlt_err_t psbtError = macwlt_last_error(self.sut);
    int ethStatus = macwlt_sign_eth_tx(self.sut, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength);
    macwlt_err_t ethError = macwlt_last_error(self.sut);
    int pubkeyStatus = macwlt_export_pubkey(self.sut, "m/84h/0h/0h/0/0", &oneByte, &oneByteLength);
    macwlt_err_t pubkeyError = macwlt_last_error(self.sut);
    int attestationStatus = macwlt_export_attestation(self.sut, &oneByte, sizeof(oneByte), &oneByte, &oneByteLength);
    macwlt_err_t attestationError = macwlt_last_error(self.sut);
    oneByteLength = sizeof(oneByte);
    int unsupportedAddressStatus = macwlt_export_address(self.sut, "m", (macwlt_address_type_t)999,
                                                         (char *)&oneByte, &oneByteLength);
    macwlt_err_t unsupportedAddressError = macwlt_last_error(self.sut);
    oneByteLength = sizeof(oneByte);
    int hardenedAddressStatus = macwlt_export_address(self.sut, "m/84h/0/0",
                                                      MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET,
                                                      (char *)&oneByte,
                                                      &oneByteLength);
    macwlt_err_t hardenedAddressError = macwlt_last_error(self.sut);

    XCTAssertEqual(psbtStatus, MACWLT_FAILURE);
    XCTAssertEqual(psbtError, MACWLT_ERR_UNAVAILABLE);
    XCTAssertEqual(ethStatus, MACWLT_FAILURE);
    XCTAssertEqual(ethError, MACWLT_ERR_UNAVAILABLE);
    XCTAssertEqual(pubkeyStatus, MACWLT_FAILURE);
    XCTAssertEqual(pubkeyError, MACWLT_ERR_UNSUPPORTED);
    XCTAssertEqual(attestationStatus, MACWLT_FAILURE);
    XCTAssertEqual(attestationError, MACWLT_ERR_UNSUPPORTED);
    XCTAssertEqual(unsupportedAddressStatus, MACWLT_FAILURE);
    XCTAssertEqual(unsupportedAddressError, MACWLT_ERR_UNSUPPORTED);
    XCTAssertEqual(hardenedAddressStatus, MACWLT_FAILURE);
    XCTAssertEqual(hardenedAddressError, MACWLT_ERR_UNSUPPORTED);
}

- (void)testRootPubkeyAndAddressExportStateAndSizingErrors {
    XCTAssertEqual(macwlt_wallet_create(&_sut), MACWLT_SUCCESS);
    uint8_t pubkey[1] = {0};
    size_t pubkeyLength = sizeof(pubkey);

    int undersizedStatus = macwlt_export_pubkey(self.sut, "m", pubkey, &pubkeyLength);
    macwlt_err_t undersizedError = macwlt_last_error(self.sut);
    uint8_t fullPubkey[33] = {0};
    pubkeyLength = sizeof(fullPubkey);
    int unavailableStatus = macwlt_export_pubkey(self.sut, "m", fullPubkey, &pubkeyLength);
    macwlt_err_t unavailableError = macwlt_last_error(self.sut);
    int nullPathStatus = macwlt_export_pubkey(self.sut, NULL, fullPubkey, &pubkeyLength);
    macwlt_err_t nullPathError = macwlt_last_error(self.sut);
    char address[64] = {0};
    size_t addressLength = sizeof(address);
    int addressStatus = macwlt_export_address(self.sut, "m",
                                              MACWLT_ADDRESS_BITCOIN_P2WPKH_MAINNET,
                                              address,
                                              &addressLength);
    macwlt_err_t addressError = macwlt_last_error(self.sut);

    XCTAssertEqual(undersizedStatus, MACWLT_FAILURE);
    XCTAssertEqual(undersizedError, MACWLT_ERR_BUFFER_TOO_SMALL);
    XCTAssertEqual(pubkeyLength, 33U);
    XCTAssertEqual(unavailableStatus, MACWLT_FAILURE);
    XCTAssertEqual(unavailableError, MACWLT_ERR_UNAVAILABLE);
    XCTAssertEqual(nullPathStatus, MACWLT_FAILURE);
    XCTAssertEqual(nullPathError, MACWLT_ERR_INVALID_ARGUMENT);
    XCTAssertEqual(addressStatus, MACWLT_FAILURE);
    XCTAssertEqual(addressError, MACWLT_ERR_UNAVAILABLE);
}

@end
