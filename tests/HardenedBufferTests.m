/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "HardenedBuffer.h"

#include <string.h>

@interface HardenedBufferTests : MacwltTestCase
@property (nonatomic, strong) HardenedBuffer *sut;
@end

@implementation HardenedBufferTests

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.sut = [HardenedBuffer bufferWithLength:32 error:&error];
    XCTAssertNotNil(self.sut, @"hardened buffer allocation failed: %@", error);
}

- (void)tearDown {
    self.sut = nil;
    [super tearDown];
}

- (void)testMaskingProtectsMemoryFromReads {
    XCTAssertEqual(self.sut.length, 32);
    XCTAssertTrue(self.sut.memoryLocked);
    XCTAssertEqual(self.sut.state, HardenedBufferStateMasked);

    NSError *error = nil;
    XCTAssertTrue([self.sut unmaskWithError:&error], @"unmask failed: %@", error);
    XCTAssertEqual(self.sut.state, HardenedBufferStateUnmasked);
    uint8_t *bytes = [self.sut mutableBytes];
    bytes[0] = 0xa5;
    XCTAssertEqual(bytes[0], 0xa5);

    XCTAssertTrue([self.sut maskWithError:&error], @"mask failed: %@", error);
    XCTAssertEqual(self.sut.state, HardenedBufferStateMasked);
    XCTAssertTrue(MacwltTestReadTriggersProtectionFault(bytes),
                  @"masked hardened buffer memory remained readable");
}

- (void)testWipeAndMaskClearsUnmaskedMemory {
    NSError *error = nil;
    XCTAssertTrue([self.sut unmaskWithError:&error], @"unmask failed: %@", error);
    uint8_t *bytes = [self.sut mutableBytes];
    memset(bytes, 0x7b, 32);

    XCTAssertTrue([self.sut wipeAndMaskWithError:&error], @"wipe failed: %@", error);
    XCTAssertEqual(self.sut.state, HardenedBufferStateMasked);
    XCTAssertTrue([self.sut unmaskWithError:&error], @"unmask after wipe failed: %@", error);
    bytes = [self.sut mutableBytes];

    XCTAssertEqual(memcmp(bytes, (uint8_t[32]){0}, 32), 0,
                   @"hardened buffer retained data after wipe");
    XCTAssertTrue([self.sut maskWithError:&error], @"remask failed: %@", error);
}

@end
