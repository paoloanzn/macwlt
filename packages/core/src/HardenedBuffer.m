/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "HardenedBuffer.h"
#import "SecureWipe.h"

#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

NSString * const HardenedBufferErrorDomain = @"macwlt.HardenedBuffer";

static NSError *hardenedBufferError(HardenedBufferErrorCode code, NSString *message) {
    return [NSError errorWithDomain:HardenedBufferErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void setHardenedBufferError(NSError **outError,
                                   HardenedBufferErrorCode code,
                                   NSString *message) {
    if (outError) *outError = hardenedBufferError(code, message);
}

static void setErrnoError(NSError **outError,
                          HardenedBufferErrorCode code,
                          NSString *operation) {
    NSString *message = [NSString stringWithFormat:@"%@ failed: %s",
                                                   operation,
                                                   strerror(errno)];
    setHardenedBufferError(outError, code, message);
}

static NSUInteger pageSize(NSError **outError) {
    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) {
        setHardenedBufferError(outError,
                               HardenedBufferErrorPageSizeUnavailable,
                               @"Could not determine system page size");
        return 0;
    }
    return (NSUInteger)pageSize;
}

static NSUInteger roundUpToPage(NSUInteger length, NSUInteger page) {
    return ((length + page - 1) / page) * page;
}

@implementation HardenedBuffer {
    void *_base;
    NSUInteger _allocatedLength;
    NSUInteger _length;
    BOOL _memoryLocked;
    HardenedBufferState _state;
}

+ (nullable instancetype)bufferWithLength:(NSUInteger)length error:(NSError **)outError {
    return [[self alloc] initWithLength:length error:outError];
}

- (nullable instancetype)initWithLength:(NSUInteger)length error:(NSError **)outError {
    if (length == 0) {
        setHardenedBufferError(outError,
                               HardenedBufferErrorInvalidLength,
                               @"Hardened buffer length must be greater than zero");
        return nil;
    }

    NSUInteger page = pageSize(outError);
    if (page == 0) return nil;

    NSUInteger allocatedLength = roundUpToPage(length, page);
    void *base = mmap(NULL,
                      allocatedLength,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON,
                      -1,
                      0);
    if (base == MAP_FAILED) {
        setErrnoError(outError,
                      HardenedBufferErrorAllocationFailed,
                      @"mmap");
        return nil;
    }

    secureWipe(base, allocatedLength);
    if (mlock(base, allocatedLength) != 0) {
        int savedErrno = errno;
        secureWipe(base, allocatedLength);
        munmap(base, allocatedLength);
        errno = savedErrno;
        setErrnoError(outError,
                      HardenedBufferErrorLockFailed,
                      @"mlock");
        return nil;
    }

    if (mprotect(base, allocatedLength, PROT_NONE) != 0) {
        int savedErrno = errno;
        munlock(base, allocatedLength);
        munmap(base, allocatedLength);
        errno = savedErrno;
        setErrnoError(outError,
                      HardenedBufferErrorProtectionFailed,
                      @"mprotect(PROT_NONE)");
        return nil;
    }

    self = [super init];
    if (self) {
        _base = base;
        _allocatedLength = allocatedLength;
        _length = length;
        _memoryLocked = YES;
        _state = HardenedBufferStateMasked;
    } else {
        mprotect(base, allocatedLength, PROT_READ | PROT_WRITE);
        secureWipe(base, allocatedLength);
        munlock(base, allocatedLength);
        munmap(base, allocatedLength);
    }
    return self;
}

- (void)dealloc {
    if (!_base) return;

    mprotect(_base, _allocatedLength, PROT_READ | PROT_WRITE);
    secureWipe(_base, _allocatedLength);
    if (_memoryLocked) munlock(_base, _allocatedLength);
    munmap(_base, _allocatedLength);
}

- (BOOL)unmaskWithError:(NSError **)outError {
    if (_state == HardenedBufferStateUnmasked) return YES;
    if (mprotect(_base, _allocatedLength, PROT_READ | PROT_WRITE) != 0) {
        setErrnoError(outError,
                      HardenedBufferErrorProtectionFailed,
                      @"mprotect(PROT_READ|PROT_WRITE)");
        return NO;
    }
    _state = HardenedBufferStateUnmasked;
    return YES;
}

- (BOOL)maskWithError:(NSError **)outError {
    if (_state == HardenedBufferStateMasked) return YES;
    if (mprotect(_base, _allocatedLength, PROT_NONE) != 0) {
        setErrnoError(outError,
                      HardenedBufferErrorProtectionFailed,
                      @"mprotect(PROT_NONE)");
        return NO;
    }
    _state = HardenedBufferStateMasked;
    return YES;
}

- (BOOL)wipeAndMaskWithError:(NSError **)outError {
    if (![self unmaskWithError:outError]) return NO;
    secureWipe(_base, _allocatedLength);
    return [self maskWithError:outError];
}

- (void *)mutableBytes {
    NSAssert(_state == HardenedBufferStateUnmasked,
             @"Hardened buffer bytes are only available while unmasked");
    return _base;
}

@end
