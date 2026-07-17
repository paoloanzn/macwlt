/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "SigningService.h"
#import "SigningServiceProtocol.h"
#import "WalletShareEnvelope.h"
#import "macwlt.h"

@interface SigningBoundaryTests : MacwltTestCase
@end

@implementation SigningBoundaryTests

- (void)testPublicSigningHeadersExposeStableBoundaryTypes {
    macwlt_wallet_t *wallet = NULL;
    macwlt_err_t err = MACWLT_OK;

    XCTAssertEqual(wallet, NULL);
    XCTAssertEqual(err, MACWLT_OK);
    XCTAssertLessThan(MACWLT_FAILURE, MACWLT_SUCCESS);
    XCTAssertNotNil(@protocol(SigningServiceProtocol));
    XCTAssertGreaterThan(SigningServiceErrorDomain.length, 0U);
    XCTAssertGreaterThan(WalletShareEnvelopeErrorDomain.length, 0U);
}

@end
