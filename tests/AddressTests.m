/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/Address.h"

@interface AddressTests : MacwltTestCase
@end

@implementation AddressTests

- (void)testMainnetP2WPKHAddressMatchesKnownVector {
    NSData *compressedPublicKey = MacwltTestDataFromHex(
        @"0279be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
    );

    NSString *address = p2wpkhAddress(compressedPublicKey, YES);

    XCTAssertEqualObjects(address, @"bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
}

- (void)testEthereumAddressMatchesKnownVector {
    NSData *generatorPublicKey = MacwltTestDataFromHex(
        @"79be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
        @"483ada7726a3c4655da4fbfc0e1108a8"
        @"fd17b448a68554199c47d08ffb10d4b8"
    );

    NSString *address = ethereumAddress(generatorPublicKey);

    XCTAssertEqualObjects(address, @"0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf");
}

- (void)testMainnetP2TRAddressUsesOneBIP341Tweak {
    NSData *compressedInternalPublicKey = MacwltTestDataFromHex(
        @"0279be667ef9dcbbac55a06295ce870b07"
        @"029bfcdb2dce28d959f2815b16f81798"
    );

    NSString *address = p2trAddress(compressedInternalPublicKey, YES);

    XCTAssertEqualObjects(address,
                          @"bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5p"
                          @"medqhyptwy6lm87hf5sspknck9");
}

@end
