/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "../core/SigningService.h"
#import "../core/SigningServiceListenerDelegate.h"

#import <Foundation/Foundation.h>

#include <stdlib.h>

static NSError *pipeRequestError(NSString *message) {
    return [NSError errorWithDomain:SigningServiceErrorDomain
                               code:MACWLT_ERR_INVALID_ARGUMENT
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSDictionary<NSString *, id> *pipeResponse(id value, NSError *error) {
    if (error) {
        return @{@"error": @{
            @"domain": error.domain,
            @"code": @(error.code),
            @"message": error.localizedDescription
        }};
    }
    NSCAssert(value, @"A successful pipe response requires a value");
    return @{@"value": value};
}

static NSDictionary<NSString *, id> *performPipeRequest(
    SigningService *service,
    NSDictionary<NSString *, id> *request) {
    NSString *operation = [request[@"operation"] isKindOfClass:NSString.class]
        ? request[@"operation"] : nil;
    if (!operation) {
        return pipeResponse(nil, pipeRequestError(@"Missing service operation"));
    }

    __block id value = nil;
    __block NSError *operationError = nil;
    if ([operation isEqualToString:@"bootstrap"]) {
        [service bootstrapWalletWithReply:^(NSData *publicKey, NSError *error) {
            value = publicKey;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"bootstrap-frost"]) {
        [service bootstrapFROSTWalletWithReply:^(NSData *publicKey, NSError *error) {
            value = publicKey;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"reset"]) {
        [service resetWalletWithReply:^(BOOL reset, NSError *error) {
            value = @(reset);
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"sign-psbt"]) {
        NSData *data = [request[@"data"] isKindOfClass:NSData.class]
            ? request[@"data"] : NSData.data;
        [service signPSBT:data withReply:^(NSData *signedPSBT, NSError *error) {
            value = signedPSBT;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"sign-digest"]) {
        NSData *data = [request[@"data"] isKindOfClass:NSData.class]
            ? request[@"data"] : NSData.data;
        [service signDigest:data withReply:^(NSData *signature, NSError *error) {
            value = signature;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"sign-eth"]) {
        NSData *data = [request[@"data"] isKindOfClass:NSData.class]
            ? request[@"data"] : NSData.data;
        [service signEthTx:data withReply:^(NSData *signature, NSError *error) {
            value = signature;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"pubkey"]) {
        NSString *path = [request[@"path"] isKindOfClass:NSString.class]
            ? request[@"path"] : @"";
        [service exportPubkeyForDerivationPath:path
                                     withReply:^(NSData *publicKey, NSError *error) {
            value = publicKey;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"address"]) {
        NSString *path = [request[@"path"] isKindOfClass:NSString.class]
            ? request[@"path"] : @"";
        NSNumber *addressType =
            [request[@"address-type"] isKindOfClass:NSNumber.class]
                ? request[@"address-type"] : @0;
        [service exportAddressForDerivationPath:path
                                    addressType:(SigningServiceAddressType)addressType.integerValue
                                      withReply:^(NSString *address, NSError *error) {
            value = address;
            operationError = error;
        }];
    } else if ([operation isEqualToString:@"attestation"]) {
        NSData *data = [request[@"data"] isKindOfClass:NSData.class]
            ? request[@"data"] : NSData.data;
        [service exportAttestationForChallenge:data
                                     withReply:^(NSData *attestation, NSError *error) {
            value = attestation;
            operationError = error;
        }];
    } else {
        operationError = pipeRequestError(@"Unknown service operation");
    }

    if (!value && !operationError) {
        operationError = [NSError errorWithDomain:SigningServiceErrorDomain
                                             code:MACWLT_ERR_INTERNAL
                                         userInfo:@{
            NSLocalizedDescriptionKey: @"Signing service did not produce a response"
        }];
    }
    return pipeResponse(value, operationError);
}

static NSData *readPipeBytes(NSFileHandle *fileHandle, NSUInteger length) {
    NSMutableData *result = [NSMutableData dataWithCapacity:length];
    while (result.length < length) {
        NSData *chunk = [fileHandle readDataOfLength:length - result.length];
        if (chunk.length == 0) return nil;
        [result appendData:chunk];
    }
    return result;
}

static int runPipeService(SigningService *service) {
    NSFileHandle *input = NSFileHandle.fileHandleWithStandardInput;
    NSFileHandle *output = NSFileHandle.fileHandleWithStandardOutput;
    while (YES) {
        NSData *requestLengthData = readPipeBytes(input, sizeof(uint64_t));
        if (!requestLengthData) return EXIT_SUCCESS;

        uint64_t requestLength = 0;
        [requestLengthData getBytes:&requestLength length:sizeof(requestLength)];
        requestLength = CFSwapInt64BigToHost(requestLength);
        if (requestLength == 0 || requestLength > 16 * 1024 * 1024) {
            return EXIT_FAILURE;
        }
        NSData *requestData =
            readPipeBytes(input, (NSUInteger)requestLength);
        if (!requestData) return EXIT_FAILURE;

        NSError *parseError = nil;
        id propertyList =
            [NSPropertyListSerialization propertyListWithData:requestData
                                                      options:NSPropertyListImmutable
                                                       format:NULL
                                                        error:&parseError];
        NSDictionary<NSString *, id> *response = nil;
        if ([propertyList isKindOfClass:NSDictionary.class]) {
            response = performPipeRequest(service, propertyList);
        } else {
            response = pipeResponse(nil, parseError ?:
                pipeRequestError(@"Invalid service request"));
        }

        NSError *serializationError = nil;
        NSData *responseData =
            [NSPropertyListSerialization dataWithPropertyList:response
                                                        format:NSPropertyListBinaryFormat_v1_0
                                                       options:0
                                                         error:&serializationError];
        if (!responseData) {
            NSLog(@"Could not serialize service response: %@", serializationError);
            return EXIT_FAILURE;
        }
        uint64_t encodedLength = CFSwapInt64HostToBig(responseData.length);
        NSData *responseLengthData =
            [NSData dataWithBytes:&encodedLength length:sizeof(encodedLength)];
        NSError *writeError = nil;
        if (![output writeData:responseLengthData error:&writeError] ||
            ![output writeData:responseData error:&writeError]) {
            NSLog(@"Could not write service response: %@", writeError);
            return EXIT_FAILURE;
        }
    }
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSError *error = nil;
        SigningService *service = [[SigningService alloc] initWithError:&error];
        if (!service) {
            NSLog(@"SigningService init failed: %@", error);
            return EXIT_FAILURE;
        }

        if ([NSProcessInfo.processInfo.environment[@"MACWLT_PIPE_RPC"]
                isEqualToString:@"1"]) {
            return runPipeService(service);
        }

        SigningServiceListenerDelegate *delegate =
            [[SigningServiceListenerDelegate alloc] initWithService:service];
        NSXPCListener *listener = [NSXPCListener serviceListener];
        listener.delegate = delegate;
        [listener resume];
        dispatch_main();
    }
    return EXIT_FAILURE;
}
