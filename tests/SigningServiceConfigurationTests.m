/*
 * Copyright (c) 2026 macwlt contributors.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MacwltTestCase.h"

static NSDictionary<NSString *, id> *MacwltTestPropertyListDictionaryAtPath(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:0
                                            error:&error];
    XCTAssertNotNil(data, @"could not read plist %@: %@", path, error);

    id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&error];
    XCTAssertTrue([propertyList isKindOfClass:NSDictionary.class],
                  @"plist %@ was not a dictionary: %@", path, error);
    return (NSDictionary<NSString *, id> *)propertyList;
}

@interface SigningServiceConfigurationTests : MacwltTestCase
@end

@implementation SigningServiceConfigurationTests

- (void)testBundleConfigurationDeclaresPrivateApplicationXPCService {
    NSDictionary<NSString *, id> *info =
        MacwltTestPropertyListDictionaryAtPath(@"packages/xpc/src/com.macwlt.SigningService-Info.plist");
    NSDictionary<NSString *, id> *xpcService = info[@"XPCService"];

    XCTAssertEqualObjects(info[@"CFBundleIdentifier"], @"com.macwlt.SigningService");
    XCTAssertTrue([xpcService isKindOfClass:NSDictionary.class]);
    XCTAssertEqualObjects(xpcService[@"ServiceType"], @"Application");
    XCTAssertEqualObjects(xpcService[@"JoinExistingSession"], @NO);
}

- (void)testEntitlementsKeepSigningServiceSandboxedAndOffline {
    NSDictionary<NSString *, id> *entitlements =
        MacwltTestPropertyListDictionaryAtPath(@"packages/xpc/src/signing-service.entitlements");
    NSArray<NSString *> *accessGroups = entitlements[@"keychain-access-groups"];

    XCTAssertEqualObjects(entitlements[@"com.apple.security.app-sandbox"], @YES);
    XCTAssertEqualObjects(entitlements[@"com.apple.security.network.client"], @NO);
    XCTAssertEqualObjects(entitlements[@"com.apple.security.network.server"], @NO);
    XCTAssertTrue([accessGroups isKindOfClass:NSArray.class]);
    XCTAssertEqual(accessGroups.count, 0U);
}

@end
