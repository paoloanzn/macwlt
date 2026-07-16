# Code Best Practices

Objective-C coding guidelines. Follow them when writing or modifying any `.h` / `.m`
file in this repo.

## Core principle

The runtime accepts almost anything and warns about almost nothing. `nil` swallows
messages and returns zero — `[nilObject doWork]` is legal and silent. The compiler
helps only where you invite it: take every invitation (`NS_ASSUME_NONNULL_BEGIN`,
generics, `NS_DESIGNATED_INITIALIZER`, `NS_UNAVAILABLE`, `switch` without `default`).
Whatever the compiler can't check, encode as a runtime assertion — never as a comment.

## Headers

Wrap every header in nullability macros. Nonnull becomes the default; `nullable` is
the deliberate exception you have to type out.

```objc
NS_ASSUME_NONNULL_BEGIN
@interface UserService : NSObject
- (User *)userWithID:(NSString *)ID;                  // both nonnull
- (nullable User *)cachedUserWithID:(NSString *)ID;   // may return nil
@end
NS_ASSUME_NONNULL_END
```

- Use lightweight generics on collections: `NSArray<Item *> *`, never bare `NSArray *`.
  Erased at runtime, but they catch real mistakes and document intent.
- Return `instancetype`, never `id`, from initializers and factory methods.
- Selectors include their colons. The method is `setObject:forKey:`, not `setObject`.

## Properties

Attribute order: `(nonatomic, memory, access)`.

- `copy` — `NSString`, `NSArray`, `NSDictionary`, `NSSet`, blocks
- `strong` — everything else
- `weak` — back-references: delegates, parent pointers
- `nonatomic` — always. `atomic` costs on every access and buys no real thread safety.

`copy` is not stylistic. These types all have mutable subclasses; `strong` lets a
caller keep a reference and mutate your state from the outside.

```objc
// BAD
@property (nonatomic, strong) NSString *name;
NSMutableString *m = [NSMutableString stringWithString:@"Alice"];
person.name = m;
[m appendString:@" (hacked)"];     // person.name changed underneath you

// GOOD
@property (nonatomic, copy) NSString *name;
```

Public `readonly`, private `readwrite`. Mutation only through methods that enforce rules.

```objc
// Order.h — what the world sees
@property (nonatomic, copy, readonly) NSArray<Item *> *items;
- (void)addItem:(Item *)item;

// Order.m — private class extension
@interface Order ()
@property (nonatomic, copy, readwrite) NSArray<Item *> *items;
@end
```

`copy` into ivars in `init`; return copies out (`return [_items copy];`). Handing out
your internal `NSMutableArray` typed as `NSArray` lets callers cast back and mutate you.

## Make bad state unrepresentable

### Valid on construction

One designated initializer; everything else funnels into it. Delete the doors you don't
want used — `NS_UNAVAILABLE` is a compile error at the call site.

```objc
// BAD — [[Connection alloc] init] gives host=nil, port=0. Valid? Unknowable.
@property (nonatomic, copy) NSString *host;
@property (nonatomic) NSInteger port;

// GOOD
NS_ASSUME_NONNULL_BEGIN
@interface Connection : NSObject
@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, readonly) NSInteger port;

- (instancetype)initWithHost:(NSString *)host
                        port:(NSInteger)port NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
```

Validate in the designated init, then assign ivars directly:

```objc
- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port {
    NSParameterAssert(host.length > 0);
    NSParameterAssert(port > 0 && port <= 65535);
    if (self = [super init]) {
        _host = [host copy];
        _port = port;
    }
    return self;
}
```

### No parallel booleans

```objc
// BAD — 2^3 = 8 representable states, 4 are legal.
// isLoading=YES + hasFailed=YES + hasData=YES means nothing, but compiles.
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL hasFailed;
@property (nonatomic) BOOL hasData;

// GOOD — 4 states, all of them legal
typedef NS_ENUM(NSInteger, LoadState) {
    LoadStateIdle, LoadStateLoading, LoadStateLoaded, LoadStateFailed,
};
@property (nonatomic, readonly) LoadState state;
```

`NS_ENUM` for exclusive states, `NS_OPTIONS` for bitmask flags.

### Exhaustive switches

**Switch over an enum you own with no `default:` case.** The missing-case warning is
the only exhaustiveness check the language offers; a `default:` silently discards it.

### Payloads

Enums can't carry payloads. Keep payloads as `nullable` properties and enforce the
correlation with the state in a single `transitionToState:` method with assertions —
never let call sites set state and payload independently.

### Immutability by default

An object with no transitions has no invalid transitions. `readonly` properties
populated in `init`, plus a `-copyWith…` method for variants. This is exactly why
`NSString` and `NSArray` are immutable and the mutable versions are opt-in subclasses.

## Invariants and error handling

The line: **programmer error → assert (crash). Environment error → `NSError`.**

### Assertions

```objc
NSParameterAssert(x);       // argument validation
NSAssert(cond, @"msg");     // internal invariant
NSCAssert(cond, @"msg");    // same, inside a C function
```

These compile out in release (`NS_BLOCK_ASSERTIONS`). That's the right default: crash
loudly in development, use real error handling for anything a user can trigger. An
invariant in a comment is a lie waiting to happen — make it executable.

```objc
// BAD
// items should never be empty when this is called
- (Money *)total { return [self.items valueForKeyPath:@"@sum.price"]; }

// GOOD
- (Money *)total {
    NSAssert(self.items.count > 0, @"total requires a non-empty order");
    return [self.items valueForKeyPath:@"@sum.price"];
}
```

Never `NSException` for recoverable conditions. Objective-C exceptions aren't designed
for control flow and ARC doesn't guarantee cleanup along the throw path.

### The NSError out-param convention

```objc
- (nullable User *)loadUserWithID:(NSString *)ID error:(NSError **)error {
    NSParameterAssert(ID.length > 0);          // programmer error → assert

    NSData *data = [self.cache dataForKey:ID];
    if (!data) {
        if (error) {                           // caller may pass NULL — always guard
            *error = [NSError errorWithDomain:MyErrorDomain
                                         code:MyErrorCodeNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Not found"}];
        }
        return nil;                            // return value signals failure
    }
    return [User userFromData:data];
}
```

**The return value is the failure signal, not the error pointer.** Only write `*error`
on a failure path.

```objc
NSError *err = nil;
[svc loadUserWithID:@"1" error:&err];
if (err) { }                          // BAD — err may be garbage on success

User *u = [svc loadUserWithID:@"1" error:&err];
if (!u) { }                           // GOOD — err guaranteed populated
```

## Retain cycles

ARC inserts retain/release but cannot see cycles. Two shapes, both mandatory to handle.

### Delegates

The back-reference is `weak`, always. Pass the sender as the first argument so one
object can be the delegate of many. Check `@optional` methods before calling.

```objc
@property (nonatomic, weak) id<DownloaderDelegate> delegate;

if ([self.delegate respondsToSelector:@selector(downloader:didFailWithError:)]) {
    [self.delegate downloader:self didFailWithError:error];
}
```

### Stored blocks

A block captures `self` strongly. If `self` holds the block, that's a cycle.

```objc
// BAD — self → block → self, neither ever deallocated
self.completion = ^{ [self.spinner stopAnimating]; };

// GOOD — the weak/strong dance
__weak typeof(self) weakSelf = self;
self.completion = ^{
    __strong typeof(self) strongSelf = weakSelf;
    if (!strongSelf) return;              // object died; bail out
    [strongSelf.spinner stopAnimating];
    [strongSelf doSomethingElse];         // can't vanish mid-block
};
```

The `strongSelf` re-capture is not ceremony — without it `weakSelf` can go nil *between
two lines* of the block, producing baffling partial execution.

Do **not** apply the dance to blocks passed as arguments and not stored
(`animateWithDuration:animations:`, `enumerateObjectsUsingBlock:`). They're released on
completion; capturing `self` strongly there is correct and the dance is noise.

## Concurrency

Private serial queue guarding mutable state. Not locks, not `atomic`.

```objc
_queue = dispatch_queue_create("com.app.cache", DISPATCH_QUEUE_SERIAL);

- (nullable id)objectForKey:(NSString *)key {
    __block id result = nil;
    dispatch_sync(self.queue, ^{ result = self.storage[key]; });
    return result;
}
- (void)setObject:(id)obj forKey:(NSString *)key {
    dispatch_async(self.queue, ^{ self.storage[key] = obj; });   // writes don't block
}
```

The invariant — *`storage` is only ever touched on `queue`* — is compiler-invisible.
Document it above the property and be ruthless about it.

## Categories

Always prefix category methods. Two categories adding `-trim` to `NSString` is
undefined behavior with no warning.

```objc
@interface NSString (MYTrimming)
- (NSString *)my_stringByTrimmingWhitespace;
@end
```

Categories cannot add ivars or stored properties. Need state? Use a class extension on
your own class. Associated objects are a last resort.

## Never

- Ship `strong` on `NSString` / `NSArray` / `NSDictionary` / `NSSet` / block properties
- Add `default:` to a `switch` over an `NS_ENUM` you own
- Use `NSException` for anything recoverable
- Check `if (error)` instead of the return value
- Write `*error` on a success path, or dereference it without a `if (error)` guard
- Store a block that captures `self` strongly
- Return an internal mutable collection typed as its immutable counterpart
- Declare a public `readwrite` property when `readonly` + a method would do
- Leave a header without `NS_ASSUME_NONNULL_BEGIN` / `END`
- Write an invariant as a comment when it could be an assertion

## Review checklist

- [ ] Header wrapped in `NS_ASSUME_NONNULL_BEGIN` / `END`; collections generic
- [ ] Value-like properties are `copy`; back-references are `weak`; all `nonatomic`
- [ ] Public surface `readonly`; no internal mutable references handed out
- [ ] One `NS_DESIGNATED_INITIALIZER`; unsupported inits marked `NS_UNAVAILABLE`
- [ ] No object can be constructed in a half-built state
- [ ] Modes/phases are `NS_ENUM`, not parallel booleans; switches have no `default:`
- [ ] Preconditions the compiler can't express are assertions, not comments
- [ ] Expected failures use `NSError` out-params; only programmer error asserts
- [ ] Every stored block does the weak/strong dance; no cycles
- [ ] Mutable state touched only on its serial queue
- [ ] Category methods prefixed