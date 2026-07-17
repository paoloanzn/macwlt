/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningServiceClient.h"

#include <dlfcn.h>
#include <stdlib.h>

NSString * const SigningServiceClientDefaultServiceName = @"com.macwlt.SigningService";

@implementation SigningServiceClient {
    dispatch_queue_t _queue;
    NSXPCConnection *_connection;
    NSTask *_serviceTask;
    NSFileHandle *_serviceInput;
    NSFileHandle *_serviceOutput;
}

+ (instancetype)clientWithDefaultService {
    return [[self alloc] initWithServiceName:SigningServiceClientDefaultServiceName];
}

- (instancetype)initWithServiceName:(NSString *)serviceName {
    NSParameterAssert(serviceName.length > 0);

    self = [super init];
    if (self) {
        _serviceName = [serviceName copy];
        _queue = dispatch_queue_create("com.macwlt.signing-service-client", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (void)invalidate {
    dispatch_sync(_queue, ^{
        [_connection invalidate];
        _connection = nil;
        [_serviceInput closeFile];
        [_serviceOutput closeFile];
        _serviceInput = nil;
        _serviceOutput = nil;
        if (_serviceTask.running) [_serviceTask terminate];
        _serviceTask = nil;
    });
}

- (nullable NSURL *)developmentServiceExecutableURL {
    Dl_info imageInfo;
    if (dladdr((__bridge const void *)SigningServiceClient.class, &imageInfo) == 0 ||
        !imageInfo.dli_fname) {
        return nil;
    }
    NSURL *imageURL = [NSURL fileURLWithPath:
        [NSString stringWithUTF8String:imageInfo.dli_fname]];
    if (![imageURL.pathExtension isEqualToString:@"dylib"] &&
        [imageURL.path rangeOfString:@".xctest/"].location == NSNotFound) {
        return nil;
    }
    NSURL *directory = [imageURL URLByDeletingLastPathComponent];
    for (NSUInteger depth = 0; depth < 6; depth++) {
        NSURL *serviceBundle = [directory
            URLByAppendingPathComponent:@"com.macwlt.SigningService.xpc"];
        NSURL *executable = [serviceBundle
            URLByAppendingPathComponent:@"Contents/MacOS/com.macwlt.SigningService"];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:executable.path]) {
            return executable;
        }
        NSURL *parent = [directory URLByDeletingLastPathComponent];
        if ([parent isEqual:directory]) break;
        directory = parent;
    }
    return nil;
}

- (nullable NSData *)readLength:(NSUInteger)length
                 fromFileHandle:(NSFileHandle *)fileHandle {
    NSMutableData *result = [NSMutableData dataWithCapacity:length];
    while (result.length < length) {
        NSData *chunk = [fileHandle readDataOfLength:length - result.length];
        if (chunk.length == 0) return nil;
        [result appendData:chunk];
    }
    return result;
}

- (BOOL)startDevelopmentServiceAtURL:(NSURL *)executableURL
                               error:(NSError **)outError {
    NSAssert(!_serviceTask, @"Development service must only be started once");
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = executableURL;
    NSMutableDictionary<NSString *, NSString *> *environment =
        [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"MACWLT_PIPE_RPC"] = @"1";
    task.environment = environment;
    NSPipe *requestPipe = [NSPipe pipe];
    NSPipe *responsePipe = [NSPipe pipe];
    task.standardInput = requestPipe;
    task.standardOutput = responsePipe;
    task.standardError = NSFileHandle.fileHandleWithStandardError;
    if (![task launchAndReturnError:outError]) return NO;

    _serviceTask = task;
    _serviceInput = requestPipe.fileHandleForWriting;
    _serviceOutput = responsePipe.fileHandleForReading;
    return YES;
}

- (void)clearDevelopmentService {
    [_serviceInput closeFile];
    [_serviceOutput closeFile];
    _serviceInput = nil;
    _serviceOutput = nil;
    if (_serviceTask.running) [_serviceTask terminate];
    _serviceTask = nil;
}

- (nullable NSDictionary<NSString *, id> *)developmentResponseForRequest:
    (NSDictionary<NSString *, id> *)request
    error:(NSError **)outError {
    NSURL *executableURL = [self developmentServiceExecutableURL];
    if (!executableURL) return nil;

    NSError *serializationError = nil;
    NSData *requestData =
        [NSPropertyListSerialization dataWithPropertyList:request
                                                    format:NSPropertyListBinaryFormat_v1_0
                                                   options:0
                                                     error:&serializationError];
    if (!requestData) {
        if (outError) *outError = serializationError;
        return @{};
    }

    __block NSData *responseData = nil;
    __block NSError *transportError = nil;
    dispatch_sync(_queue, ^{
        if (!_serviceTask &&
            ![self startDevelopmentServiceAtURL:executableURL
                                          error:&transportError]) {
            return;
        }

        uint64_t encodedLength = CFSwapInt64HostToBig(requestData.length);
        NSData *lengthData = [NSData dataWithBytes:&encodedLength
                                             length:sizeof(encodedLength)];
        if (![_serviceInput writeData:lengthData error:&transportError] ||
            ![_serviceInput writeData:requestData error:&transportError]) {
            [self clearDevelopmentService];
            return;
        }

        NSData *responseLengthData =
            [self readLength:sizeof(uint64_t) fromFileHandle:_serviceOutput];
        if (!responseLengthData) {
            transportError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                  code:NSFileReadUnknownError
                                              userInfo:@{
                NSLocalizedDescriptionKey: @"Signing service process closed its response stream"
            }];
            [self clearDevelopmentService];
            return;
        }
        uint64_t responseLength = 0;
        [responseLengthData getBytes:&responseLength length:sizeof(responseLength)];
        responseLength = CFSwapInt64BigToHost(responseLength);
        if (responseLength == 0 || responseLength > 16 * 1024 * 1024) {
            transportError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                  code:NSFileReadCorruptFileError
                                              userInfo:@{
                NSLocalizedDescriptionKey: @"Signing service returned an invalid response length"
            }];
            [self clearDevelopmentService];
            return;
        }
        responseData = [self readLength:(NSUInteger)responseLength
                         fromFileHandle:_serviceOutput];
        if (!responseData) {
            transportError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                  code:NSFileReadUnknownError
                                              userInfo:@{
                NSLocalizedDescriptionKey: @"Signing service returned a truncated response"
            }];
            [self clearDevelopmentService];
        }
    });
    if (!responseData) {
        if (outError) *outError = transportError;
        return @{};
    }

    NSError *parseError = nil;
    id propertyList =
        [NSPropertyListSerialization propertyListWithData:responseData
                                                  options:NSPropertyListImmutable
                                                   format:NULL
                                                    error:&parseError];
    if (![propertyList isKindOfClass:NSDictionary.class]) {
        if (outError) *outError = parseError;
        return @{};
    }
    return (NSDictionary<NSString *, id> *)propertyList;
}

- (nullable id)developmentValueForRequest:(NSDictionary<NSString *, id> *)request
                            expectedClass:(Class)expectedClass
                                    error:(NSError **)outError {
    NSDictionary<NSString *, id> *response =
        [self developmentResponseForRequest:request error:outError];
    if (!response) return nil;
    if (response.count == 0) return nil;

    NSDictionary<NSString *, id> *errorRecord =
        [response[@"error"] isKindOfClass:NSDictionary.class]
            ? response[@"error"] : nil;
    if (errorRecord) {
        NSString *domain = [errorRecord[@"domain"] isKindOfClass:NSString.class]
            ? errorRecord[@"domain"] : NSCocoaErrorDomain;
        NSNumber *code = [errorRecord[@"code"] isKindOfClass:NSNumber.class]
            ? errorRecord[@"code"] : @0;
        NSString *message = [errorRecord[@"message"] isKindOfClass:NSString.class]
            ? errorRecord[@"message"] : @"Signing service request failed";
        if (outError) {
            *outError = [NSError errorWithDomain:domain
                                             code:code.integerValue
                                         userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    id value = response[@"value"];
    if (expectedClass && ![value isKindOfClass:expectedClass]) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSPropertyListReadCorruptError
                                         userInfo:@{
                NSLocalizedDescriptionKey: @"Signing service returned an invalid response"
            }];
        }
        return nil;
    }
    return value;
}

- (id<SigningServiceProtocol>)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler {
    NSParameterAssert(handler);

    __block NSXPCConnection *connection = nil;
    dispatch_sync(_queue, ^{
        if (!_connection) {
            _connection = [[NSXPCConnection alloc] initWithServiceName:self.serviceName];
            _connection.remoteObjectInterface =
                [NSXPCInterface interfaceWithProtocol:@protocol(SigningServiceProtocol)];
            [_connection resume];
        }
        connection = _connection;
    });

    id proxy = [connection remoteObjectProxyWithErrorHandler:handler];
    return (id<SigningServiceProtocol>)proxy;
}

- (void)bootstrapWalletWithReply:(SigningServiceBootstrapReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{@"operation": @"bootstrap"}
                                           expectedClass:NSData.class
                                                   error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote bootstrapWalletWithReply:reply];
}

- (void)bootstrapFROSTWalletWithReply:(SigningServiceBootstrapReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{@"operation": @"bootstrap-frost"}
                                           expectedClass:NSData.class
                                                   error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote bootstrapFROSTWalletWithReply:reply];
}

- (void)resetWalletWithReply:(SigningServiceResetReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSNumber *value = [self developmentValueForRequest:@{@"operation": @"reset"}
                                             expectedClass:NSNumber.class
                                                     error:&error];
        reply(value.boolValue, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(NO, error);
        }];
    [remote resetWalletWithReply:reply];
}

- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{
            @"operation": @"sign-psbt",
            @"data": psbt
        } expectedClass:NSData.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote signPSBT:psbt withReply:reply];
}

- (void)signDigest:(NSData *)digest withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{
            @"operation": @"sign-digest",
            @"data": digest
        } expectedClass:NSData.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote signDigest:digest withReply:reply];
}

- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{
            @"operation": @"sign-eth",
            @"data": transaction
        } expectedClass:NSData.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote signEthTx:transaction withReply:reply];
}

- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{
            @"operation": @"pubkey",
            @"path": derivationPath
        } expectedClass:NSData.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote exportPubkeyForDerivationPath:derivationPath withReply:reply];
}

- (void)exportAddressForDerivationPath:(NSString *)derivationPath
                            addressType:(SigningServiceAddressType)addressType
                              withReply:(SigningServiceAddressReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSString *value = [self developmentValueForRequest:@{
            @"operation": @"address",
            @"path": derivationPath,
            @"address-type": @(addressType)
        } expectedClass:NSString.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote exportAddressForDerivationPath:derivationPath
                               addressType:addressType
                                 withReply:reply];
}

- (void)exportAttestationForChallenge:(NSData *)challenge
                            withReply:(SigningServiceAttestationReply)reply {
    NSParameterAssert(reply);

    if ([self developmentServiceExecutableURL]) {
        NSError *error = nil;
        NSData *value = [self developmentValueForRequest:@{
            @"operation": @"attestation",
            @"data": challenge
        } expectedClass:NSData.class error:&error];
        reply(value, error);
        return;
    }
    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote exportAttestationForChallenge:challenge withReply:reply];
}

@end
