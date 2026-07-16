/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "HardenedShareWindow.h"

NSString * const HardenedShareWindowErrorDomain = @"macwlt.HardenedShareWindow";

static NSError *shareWindowError(HardenedShareWindowErrorCode code, NSString *message) {
    return [NSError errorWithDomain:HardenedShareWindowErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setShareWindowError(NSError **outError,
                                HardenedShareWindowErrorCode code,
                                NSString *message) {
    if (outError) *outError = shareWindowError(code, message);
}

@implementation HardenedShareWindow {
    HardenedBuffer *_shareABuffer;
    HardenedBuffer *_shareBBuffer;
    NSUInteger _shareLength;
}

+ (nullable instancetype)windowWithShareLength:(NSUInteger)shareLength
                                         error:(NSError **)outError {
    return [[self alloc] initWithShareLength:shareLength error:outError];
}

- (nullable instancetype)initWithShareLength:(NSUInteger)shareLength
                                       error:(NSError **)outError {
    if (shareLength == 0) {
        setShareWindowError(outError,
                            HardenedShareWindowErrorInvalidShareLength,
                            @"Share window length must be greater than zero");
        return nil;
    }

    HardenedBuffer *shareABuffer = [HardenedBuffer bufferWithLength:shareLength
                                                              error:outError];
    if (!shareABuffer) return nil;

    HardenedBuffer *shareBBuffer = [HardenedBuffer bufferWithLength:shareLength
                                                              error:outError];
    if (!shareBBuffer) return nil;

    self = [super init];
    if (self) {
        _shareABuffer = shareABuffer;
        _shareBBuffer = shareBBuffer;
        _shareLength = shareLength;
    }
    return self;
}

- (NSUInteger)shareLength {
    return _shareLength;
}

- (BOOL)allMemoryLocked {
    return _shareABuffer.memoryLocked && _shareBBuffer.memoryLocked;
}

- (HardenedBufferState)shareAState {
    return _shareABuffer.state;
}

- (HardenedBufferState)shareBState {
    return _shareBBuffer.state;
}

- (BOOL)performWithShareALoader:(HardenedShareWindowLoadBlock)shareALoader
                       shareAUse:(HardenedShareWindowUseBlock)shareAUse
                    shareBLoader:(HardenedShareWindowLoadBlock)shareBLoader
                       shareBUse:(HardenedShareWindowUseBlock)shareBUse
                           error:(NSError **)outError {
    if (!shareALoader || !shareAUse || !shareBLoader || !shareBUse) {
        setShareWindowError(outError,
                            HardenedShareWindowErrorInvalidBlock,
                            @"Share window requires loaders and use blocks for both shares");
        return NO;
    }

    if (![self performWindowWithBuffer:_shareABuffer
                           otherBuffer:_shareBBuffer
                                loader:shareALoader
                                   use:shareAUse
                                 error:outError]) {
        return NO;
    }

    return [self performWindowWithBuffer:_shareBBuffer
                             otherBuffer:_shareABuffer
                                  loader:shareBLoader
                                     use:shareBUse
                                   error:outError];
}

- (BOOL)performWindowWithBuffer:(HardenedBuffer *)buffer
                    otherBuffer:(HardenedBuffer *)otherBuffer
                         loader:(HardenedShareWindowLoadBlock)loader
                            use:(HardenedShareWindowUseBlock)use
                          error:(NSError **)outError {
    if (buffer.state != HardenedBufferStateMasked ||
        otherBuffer.state != HardenedBufferStateMasked) {
        setShareWindowError(outError,
                            HardenedShareWindowErrorUnexpectedState,
                            @"Share windows must start with both hardened buffers masked");
        return NO;
    }

    if (!loader(buffer, outError)) return NO;

    if (otherBuffer.state != HardenedBufferStateMasked) {
        [buffer wipeAndMaskWithError:NULL];
        [otherBuffer wipeAndMaskWithError:NULL];
        setShareWindowError(outError,
                            HardenedShareWindowErrorUnexpectedState,
                            @"Share windows must never overlap");
        return NO;
    }

    if (buffer.state != HardenedBufferStateUnmasked) {
        setShareWindowError(outError,
                            HardenedShareWindowErrorLoaderDidNotUnmask,
                            @"Share loader must leave exactly one hardened buffer unmasked");
        return NO;
    }

    BOOL used = use((const uint8_t *)[buffer mutableBytes], _shareLength, outError);

    NSError *cleanupError = nil;
    BOOL cleaned = [buffer wipeAndMaskWithError:&cleanupError];
    if (!used) return NO;
    if (!cleaned) {
        if (outError) *outError = cleanupError;
        return NO;
    }

    if (otherBuffer.state != HardenedBufferStateMasked) {
        setShareWindowError(outError,
                            HardenedShareWindowErrorUnexpectedState,
                            @"Other share buffer opened during cleanup");
        return NO;
    }
    return YES;
}

@end
