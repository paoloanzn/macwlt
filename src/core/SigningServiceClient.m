/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "SigningServiceClient.h"

NSString * const SigningServiceClientDefaultServiceName = @"com.macwlt.SigningService";

@implementation SigningServiceClient {
    dispatch_queue_t _queue;
    NSXPCConnection *_connection;
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
    });
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

    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote bootstrapWalletWithReply:reply];
}

- (void)signPSBT:(NSData *)psbt withReply:(SigningServicePSBTReply)reply {
    NSParameterAssert(reply);

    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote signPSBT:psbt withReply:reply];
}

- (void)signEthTx:(NSData *)transaction withReply:(SigningServiceSignatureReply)reply {
    NSParameterAssert(reply);

    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote signEthTx:transaction withReply:reply];
}

- (void)exportPubkeyForDerivationPath:(NSString *)derivationPath
                            withReply:(SigningServicePubkeyReply)reply {
    NSParameterAssert(reply);

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

    id<SigningServiceProtocol> remote =
        [self remoteObjectProxyWithErrorHandler:^(NSError *error) {
            reply(nil, error);
        }];
    [remote exportAttestationForChallenge:challenge withReply:reply];
}

@end
