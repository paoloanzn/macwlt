# TESTS.md

Objective-C testing guidelines. Companion to the
[core Objective-C coding practices](../packages/core/CLAUDE.md) — that guide covers
writing production code, this one covers proving it works. Follow when writing or
modifying anything under `tests/`.

Build: clang + Makefile on macOS. There is no `.xcodeproj`. XCTest is available anyway
— it ships in the Xcode toolchain, not the project format — but every convenience
`xcodebuild` provided (schemes, `-only-testing:`, parallelization, coverage flags) is
ours to wire by hand. See § Building and running.

## Core principle

Coverage tells you what executed, not what was verified. The metric that matters:
**when a test fails, do you know what broke without opening the debugger?** Test the
seams where bad state enters — parsers, factories, designated inits, state transitions,
error paths. Testing a synthesized setter tests the compiler.

## Framework

XCTest only. Expecta / Kiwi / Specta are 2014-era and are maintenance liabilities now.
OCMock is allowed under the narrow rules below.

## Discovery

Two mechanisms, both silent when they fail.

**Method level.** Test methods start with `test`, take no arguments, return `void`.
A typo (`tsetAddingItem`) means the test never runs. This is the single most common
cause of "we have 400 tests and this bug shipped anyway."

**Class level.** `xctest` `dlopen`s the bundle and finds `XCTestCase` subclasses by
runtime introspection. Nothing references them statically, so **without `-ObjC` the
linker strips them** and the class vanishes from the run with no error. If a whole
suite disappears, check `-ObjC` before anything else.

When adding a test, confirm the reported count went up.

## Structure

One test class per production class. `OrderTests` for `Order`. Property named `sut`
(system under test).

```objc
@interface OrderTests : XCTestCase
@property (nonatomic, strong) Order *sut;
@end

@implementation OrderTests

- (void)setUp {
    [super setUp];
    self.sut = [[Order alloc] initWithCustomerID:@"C1"];
}

- (void)tearDown {
    self.sut = nil;       // do this even under ARC — surfaces lifecycle bugs
    [super tearDown];
}

- (void)testAddingItemIncreasesTotal {
    Item *item = [Item itemWithPrice:1000];

    [self.sut addItem:item];

    XCTAssertEqual(self.sut.total.cents, 1000);
}

@end
```

Arrange / Act / Assert, blank line between each. It must be visually obvious which
line is the act.

- **Name the behavior, not the method.** `testAddingDuplicateItemMergesQuantity`, not
  `testAddItem`. The name must explain the failure from the CI log alone.
- **One reason to fail per test** — not one `XCTAssert`. Checking three fields of one
  returned object is one logical assertion.
- **No `if` / `for` / `switch` in a test body.** A test with a branch has an untested
  branch.
- Tests never depend on execution order.

## Assertions

```objc
XCTAssertEqual(a, b);                       // scalars — uses ==
XCTAssertEqualObjects(a, b);                // objects — uses -isEqual:
XCTAssertEqualWithAccuracy(a, b, 0.001);    // floats. always.
XCTAssertNil(x);
XCTAssertTrue(cond);
XCTAssertThrows(expr);
```

`XCTAssertEqual` on objects compares **pointers**. It passes by accident for literals
(compiler interning) and fails for runtime-constructed strings.

```objc
// BAD — compares pointers
XCTAssertEqual(user.name, @"Alice");

// GOOD
XCTAssertEqualObjects(user.name, @"Alice");
```

**A failed assert does not stop the method.** Guard before dereferencing, or a nil
crash takes down the whole bundle process and you lose every result after it.

```objc
// BAD
XCTAssertNotNil(user);
XCTAssertEqualObjects(user.name, @"Alice");   // crashes if nil

// GOOD
User *user = [svc loadUser];
if (!user) { XCTFail(@"expected a user"); return; }
XCTAssertEqualObjects(user.name, @"Alice");
```

(`XCTUnwrap` exists but needs `NSError **` plumbing in Objective-C; the guard idiom is
what gets used.)

Add a message wherever the failure would be ambiguous:

```objc
XCTAssertEqual(results.count, 3, @"expected 3 results for query %@, got %@", query, results);
```

## Testing the core coding contracts

### Preconditions

`NSParameterAssert` compiles out when `NS_BLOCK_ASSERTIONS` is defined, so these tests
are live only in debug builds. The test target must never inherit that flag — see
§ Build config is part of the test contract.

```objc
- (void)testEmptyHostIsRejected {
    XCTAssertThrows([[Connection alloc] initWithHost:@"" port:80]);
}
```

### The NSError out-param contract

These three are the tests nobody writes, and they're exactly the contract violations
that leak into production.

```objc
- (void)testLoadingUnknownUserReturnsNotFoundError {
    NSError *error = nil;
    User *user = [self.sut loadUserWithID:@"missing" error:&error];

    XCTAssertNil(user);                                 // return value is the signal
    XCTAssertEqualObjects(error.domain, MyErrorDomain);
    XCTAssertEqual(error.code, MyErrorCodeNotFound);
}

- (void)testSuccessDoesNotTouchErrorOutParam {
    NSError *error = (NSError *)[NSNull null];          // poison it
    User *user = [self.sut loadUserWithID:@"known" error:&error];

    XCTAssertNotNil(user);
    XCTAssertEqualObjects(error, (NSError *)[NSNull null], @"must not write *error on success");
}

- (void)testNullErrorParamDoesNotCrash {
    XCTAssertNil([self.sut loadUserWithID:@"missing" error:NULL]);
}
```

### Retain cycles

Every class that stores a block or registers as a delegate gets a leak test. The
`@autoreleasepool` is required — without it `vc` sits in the pool and the test fails
spuriously.

These tests are also why test builds are `-O0`: the optimizer is free to move releases
around, and at `-Os` a leak test can pass or fail for reasons unrelated to your code.

```objc
- (void)testViewControllerDoesNotLeak {
    __weak MyViewController *weakVC = nil;
    @autoreleasepool {
        MyViewController *vc = [[MyViewController alloc] init];
        weakVC = vc;
        [vc viewDidLoad];
        [vc startDownload];         // installs the completion block
    }
    XCTAssertNil(weakVC, @"leaked — check block captures");
}
```

## Test doubles

**Fake what you own. Mock what you don't.**

Protocol-based injection is the idiom. Hand-written fakes are ~15 lines, compile-checked,
and refactor cleanly.

```objc
// Production: the seam is a protocol
@protocol UserStore <NSObject>
- (nullable NSData *)dataForKey:(NSString *)key;
@end

@interface UserService : NSObject
- (instancetype)initWithStore:(id<UserStore>)store NS_DESIGNATED_INITIALIZER;
@end
```

```objc
// Test file: the fake
@interface FakeUserStore : NSObject <UserStore>
@property (nonatomic, copy, nullable) NSData *stubbedData;
@property (nonatomic, copy, nullable) NSString *lastRequestedKey;
@end

@implementation FakeUserStore
- (NSData *)dataForKey:(NSString *)key {
    self.lastRequestedKey = key;
    return self.stubbedData;
}
@end
```

If a class needs a mock to be testable, the seam is wrong — add the protocol instead.

OCMock is for framework classes you can't inject (`NSUserDefaults`,
`NSNotificationCenter`, `UIApplication`) and partial mocks of legacy classes with no
seams. It's string-and-runtime based: a renamed method breaks at runtime, not compile
time. Budget accordingly.

```objc
id mockDefaults = OCMClassMock([NSUserDefaults class]);
OCMStub([mockDefaults standardUserDefaults]).andReturn(mockDefaults);
OCMStub([mockDefaults boolForKey:@"hasOnboarded"]).andReturn(YES);
// ...
OCMVerify([mockDefaults setBool:YES forKey:@"hasOnboarded"]);
```

**`stopMocking` in `tearDown` is not optional.** A class mock swizzles the real class;
a leaked one poisons every later test in the process and fails in an unrelated file.
With a single-process runner and no per-class isolation, this is worse here than it is
under `xcodebuild`.

```objc
- (void)tearDown {
    [self.mockDefaults stopMocking];
    self.mockDefaults = nil;
    [super tearDown];
}
```

## Async

The single biggest source of flaky tests.

For callback-based APIs, use an expectation:

```objc
- (void)testDownloadCallsBackWithData {
    XCTestExpectation *expectation = [self expectationWithDescription:@"download completes"];

    [self.sut downloadURL:url completion:^(NSData *data, NSError *error) {
        XCTAssertNotNil(data);
        XCTAssertNil(error);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}
```

For code guarded by a private serial queue (see
[Concurrency](../packages/core/CLAUDE.md#concurrency)), don't use an expectation — use
a **fence**. An empty `dispatch_sync` returns once everything queued before it has
drained. Deterministic, unlike a timeout. Prefer it wherever the concurrency is
queue-based.

```objc
// Cache+Testing.h — exposed to tests only
- (void)waitForPendingOperations {
    dispatch_sync(self.queue, ^{});
}
```

Rules:

- **Never `sleep()` or `[NSThread sleepForTimeInterval:]`.** Either too short (flaky)
  or too long (slow), usually both.
- Timeouts stay short (1–2s). A long timeout hides a hang instead of reporting it.
- An expectation fulfilled twice is a hard failure — that's a real bug in your callback.
  Leave `assertForOverFulfill` on.
- Never `dispatch_sync` to the main queue from a test on the main thread. Instant deadlock.

## Building and running

XCTest tests are a **bundle**, not an executable. `xctest` `dlopen`s the `.xctest`
bundle and finds the classes at runtime. Two flags are load-bearing:

- `-bundle` — link as a loadable bundle. An executable will not run under `xctest`.
- `-ObjC` — keep the test classes. Nothing references them statically; without this
  the linker strips them and they vanish silently.

Resolve the toolchain with `xcode-select -p`. Hardcoding `/Applications/Xcode.app`
breaks on CI runners and any machine with Xcode-beta.

```make
DEVDIR       := $(shell xcode-select -p)
PLATFORM     := $(DEVDIR)/Platforms/MacOSX.platform/Developer
FRAMEWORKS   := $(PLATFORM)/Library/Frameworks
XCTEST       := $(PLATFORM)/usr/bin/xctest

BUNDLE       := build/MyLibTests.xctest
BINARY       := $(BUNDLE)/Contents/MacOS/MyLibTests

TEST_SRCS    := $(wildcard tests/*.m)
LIB_SRCS     := $(wildcard src/*.m)

# Test CFLAGS are deliberately separate from release CFLAGS. Do not merge them.
TEST_CFLAGS  := -fobjc-arc -g -O0 -Wall -Werror -Isrc \
                -fmodules -F$(FRAMEWORKS) -iframework $(FRAMEWORKS)
TEST_LDFLAGS := -bundle -ObjC \
                -F$(FRAMEWORKS) -framework XCTest -framework Foundation \
                -Wl,-rpath,$(FRAMEWORKS)

$(BINARY): $(TEST_SRCS) $(LIB_SRCS)
	@mkdir -p $(dir $@)
	clang $(TEST_CFLAGS) $(TEST_LDFLAGS) $^ -o $@

# make test
# make test FILTER=OrderTests
# make test FILTER=OrderTests/testAddingItemIncreasesTotal
XCTEST_FILTER := $(if $(FILTER),-XCTest MyLibTests.$(FILTER),)

test: $(BINARY)
	$(XCTEST) $(XCTEST_FILTER) $(BUNDLE)

.PHONY: test
```

`-O0` is not negotiable for the test target: the leak tests depend on ARC releasing
where the source says it does.

### Build config is part of the test contract

`xcodebuild` managed `NS_BLOCK_ASSERTIONS` per-configuration. A Makefile does not. If
`-DNS_BLOCK_ASSERTIONS` reaches the test target — usually via a shared `CFLAGS`
variable someone added for release — **every `XCTAssertThrows` precondition test
silently passes**. Keep `TEST_CFLAGS` separate from release `CFLAGS`, and pin it with
a test:

```objc
- (void)testAssertionsAreEnabledInThisTarget {
#ifdef NS_BLOCK_ASSERTIONS
    XCTFail(@"NS_BLOCK_ASSERTIONS is set — every precondition test is a no-op");
#endif
}
```

A test about the build config is unusual. The failure it prevents is invisible otherwise.

### Parallelization

There is no scheme, so there is no per-class parallelization. `xctest` runs one bundle
in one process, sequentially.

That removes the cheap check for hidden shared state (singletons, leaked class mocks,
`NSUserDefaults`) — the bug is still real, it just stops announcing itself. Recover a
coarse version by sharding across processes in CI:

```make
shard: $(BINARY)
	$(XCTEST) -XCTest MyLibTests.OrderTests $(BUNDLE) &
	$(XCTEST) -XCTest MyLibTests.CacheTests $(BUNDLE) &
	wait
```

Isolation is per-invocation rather than per-class, so it catches less. Run it anyway.

### Coverage

No `-enableCodeCoverage`. Instrument by hand:

```make
COVFLAGS := -fprofile-instr-generate -fcoverage-mapping   # add to CFLAGS and LDFLAGS

coverage: $(BINARY)
	LLVM_PROFILE_FILE=build/tests.profraw $(XCTEST) $(BUNDLE)
	xcrun llvm-profdata merge -sparse build/tests.profraw -o build/tests.profdata
	xcrun llvm-cov report $(BINARY) -instr-profile=build/tests.profdata
```

Use as a **negative** signal only: uncovered error paths are real gaps. Never as a
target — percentage mandates produce tests written to touch lines, which is worse than
no test because it looks like protection.

## Never

- `XCTAssertEqual` on objects
- `XCTAssertEqual` on floats without an accuracy
- `XCTAssertNotNil(x)` followed immediately by `x.foo`
- `sleep()` or `[NSThread sleepForTimeInterval:]` anywhere
- `if` / `for` / `switch` in a test body
- A class mock without `stopMocking` in `tearDown`
- Asserting on `error` instead of the return value
- Mocking a type you own instead of injecting a protocol
- Real network, real disk, real clock — inject a date provider
- Tests that depend on execution order
- A test name describing the method instead of the expected behavior
- A leak test without `@autoreleasepool`
- Linking the test bundle without `-ObjC` (classes vanish silently)
- Linking tests as an executable instead of `-bundle`
- Hardcoding the Xcode path instead of `xcode-select -p`
- Test `CFLAGS` sharing a variable with release `CFLAGS`
- `-DNS_BLOCK_ASSERTIONS` anywhere near the test target
- Optimization above `-O0` in test builds

## Review checklist

- [ ] Method starts with `test`; suite count went up
- [ ] Name describes the behavior, not the method
- [ ] Arrange / Act / Assert, one reason to fail, no branches
- [ ] `XCTAssertEqualObjects` for objects, accuracy for floats
- [ ] Guarded before every dereference of a possibly-nil value
- [ ] Error paths: return value checked first, then domain and code
- [ ] `*error` untouched on success; `NULL` out-param doesn't crash
- [ ] Preconditions tested via `XCTAssertThrows`
- [ ] Leak test for any class storing blocks or delegates
- [ ] Fakes for owned types; OCMock only for framework classes, with `stopMocking`
- [ ] Async uses expectations or a queue fence — no sleeps
- [ ] New test classes actually appear in the run (check `-ObjC` if not)
- [ ] `make test` green from clean; no assertions blocked
