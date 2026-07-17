/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

#import "../src/core/HardenedShareWindow.h"

#include <string.h>

static BOOL MacwltTestLoadSharePattern(HardenedBuffer *buffer,
                                       uint8_t pattern,
                                       NSError **outError) {
    if (![buffer unmaskWithError:outError]) return NO;
    memset([buffer mutableBytes], pattern, buffer.length);
    return YES;
}

@interface HardenedShareWindowTests : MacwltTestCase
@property (nonatomic, strong) HardenedShareWindow *sut;
@end

@implementation HardenedShareWindowTests

- (void)setUp {
    [super setUp];

    NSError *error = nil;
    self.sut = [HardenedShareWindow windowWithShareLength:32 error:&error];
    XCTAssertNotNil(self.sut, @"share window allocation failed: %@", error);
}

- (void)tearDown {
    self.sut = nil;
    [super tearDown];
}

- (void)testPerformingUsesSharesSequentiallyAndReturnsMasked {
    NSMutableArray<NSString *> *events = [NSMutableArray array];
    NSError *error = nil;

    BOOL ok = [self.sut performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                      NSError **outError) {
        XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
        XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
        [events addObject:@"loadA"];
        return MacwltTestLoadSharePattern(targetBuffer, 0xa1, outError);
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)outError;
        XCTAssertEqual(shareLength, 32);
        XCTAssertEqual(shareBytes[0], 0xa1);
        XCTAssertEqual(self.sut.shareAState, HardenedBufferStateUnmasked);
        XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
        [events addObject:@"useA"];
        return YES;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
        XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
        [events addObject:@"loadB"];
        return MacwltTestLoadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)outError;
        XCTAssertEqual(shareLength, 32);
        XCTAssertEqual(shareBytes[0], 0xb2);
        XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
        XCTAssertEqual(self.sut.shareBState, HardenedBufferStateUnmasked);
        [events addObject:@"useB"];
        return YES;
    } error:&error];

    XCTAssertTrue(ok, @"share window sequencing failed: %@", error);
    XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
    XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
    XCTAssertEqualObjects(events, (@[@"loadA", @"useA", @"loadB", @"useB"]));
}

- (void)testShareUseFailurePreservesErrorAndMasksBothShares {
    NSError *error = nil;

    BOOL ok = [self.sut performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                      NSError **outError) {
        return MacwltTestLoadSharePattern(targetBuffer, 0xa1, outError);
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        *outError = [NSError errorWithDomain:@"macwlt.tests"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"expected failure"}];
        return NO;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        return MacwltTestLoadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        XCTFail(@"share B should not run after share A failure");
        return NO;
    } error:&error];

    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, @"macwlt.tests");
    XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
    XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
}

- (void)testShareLoaderFailurePreservesErrorAndMasksBothShares {
    NSError *error = nil;

    BOOL ok = [self.sut performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
                                                      NSError **outError) {
        XCTAssertTrue(MacwltTestLoadSharePattern(targetBuffer, 0xa1, outError));
        *outError = [NSError errorWithDomain:@"macwlt.tests"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"expected loader failure"}];
        return NO;
    } shareAUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        XCTFail(@"share A use should not run after loader failure");
        return NO;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        return MacwltTestLoadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        XCTFail(@"share B should not run after share A loader failure");
        return NO;
    } error:&error];

    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, @"macwlt.tests");
    XCTAssertEqual(error.code, 2);
    XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
    XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
}

- (void)testClosedLoaderReturnsLoaderStateError {
    NSError *error = nil;

    BOOL ok = [self.sut performWithShareALoader:^BOOL(HardenedBuffer *targetBuffer,
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
        XCTFail(@"share A use should not run when loader leaves buffer masked");
        return NO;
    } shareBLoader:^BOOL(HardenedBuffer *targetBuffer,
                         NSError **outError) {
        return MacwltTestLoadSharePattern(targetBuffer, 0xb2, outError);
    } shareBUse:^BOOL(const uint8_t *shareBytes,
                      NSUInteger shareLength,
                      NSError **outError) {
        (void)shareBytes;
        (void)shareLength;
        (void)outError;
        return YES;
    } error:&error];

    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, HardenedShareWindowErrorDomain);
    XCTAssertEqual(error.code, HardenedShareWindowErrorLoaderDidNotUnmask);
    XCTAssertEqual(self.sut.shareAState, HardenedBufferStateMasked);
    XCTAssertEqual(self.sut.shareBState, HardenedBufferStateMasked);
}

@end
