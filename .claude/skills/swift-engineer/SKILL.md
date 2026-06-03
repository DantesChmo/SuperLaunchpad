---
name: swift-engineer
description: Idiomatic modern Swift (5.9+) coding guidance — value vs reference semantics, optionals and error handling (`try?` vs `do/catch`, `Result`, typed throws), Swift Concurrency (async/await, `Task`, `Task.detached`, `@MainActor`, actors, `AsyncSequence`, structured cancellation, Sendable), generics and protocol-oriented design, property wrappers, result builders, macros, the Observation framework (`@Observable`, `@Bindable`), Codable, memory management (`weak`/`unowned`, capture lists, retain cycles), API design (naming, mutability, access control), and Swift Testing (`import Testing`, `@Test`, `#expect`). Use when writing or reviewing Swift code, choosing between language-level approaches, or modernising older Swift idioms (NotificationCenter→AsyncSequence, completion handlers→async/await, ObservableObject→@Observable, XCTest→swift-testing).
---

# Swift engineer

You write and review Swift code with the taste of someone who's read the Swift Evolution proposals. The bar is *idiomatic, modern, minimal*. The repo's conventions (in `AGENTS.md`) override anything here when they conflict.

## Operating principles

1. **Follow the project's Swift style first** (`AGENTS.md` → "Conventions → Swift style"). Don't impose general Swift fashion if the repo has settled on something different.
2. **Smallest change that solves the problem.** No drive-by modernisation. If you spot something to fix nearby, mention it; don't fold it into an unrelated diff.
3. **Default to value types** (`struct`, `enum`). Reach for `class` only when you need identity, inheritance, or AppKit interop.
4. **Concurrency-correct, not concurrency-flavoured.** Sprinkling `async` everywhere is not concurrency — pick the actor isolation deliberately.
5. **No defensive code for impossible states.** Trust internal invariants; validate at boundaries.

## Reference — idioms

### Errors & optionals

- `try?` + explicit default for "this can fail; here's the fallback" — preferred in this repo:
  ```swift
  let apps = (try? database?.fetchAllApps()) ?? []
  ```
- `do/catch` only when the error path needs distinct behaviour (logging, retry, user-facing error).
- `try!` is allowed only for invariants enforced by tests (e.g. `try! Regex(#"…"#)` with a literal).
- Force unwrap `!` is forbidden outside `lazy` initialisers where the dependency is guaranteed.
- `guard let` for early exits; don't use `guard` for the happy path.
- Prefer specific errors over `throws -> any Error`. With Swift 6, use **typed throws** (`throws(MyError)`) when the caller branches on the error.

### Optionals

- `??` for defaults, `map`/`flatMap` for transforming, `if let`/`guard let` for unwrapping, `?.` for chaining.
- Avoid `Optional<T>` in stored properties when an empty value (`[]`, `""`) is semantically equivalent.
- Avoid double optionals (`T??`). They're almost always a bug in the call site.

### Concurrency (Swift Concurrency)

- **Pick the actor isolation deliberately.**
  - `@MainActor` — UI state, view models, anything SwiftUI binds to.
  - `actor` — mutable shared state isolated from main.
  - nonisolated — pure functions, value-only computation.
- **`Task { … }` vs `Task.detached { … }`:** `Task {}` inherits actor + priority; `Task.detached {}` does not. Detach for genuinely background work that shouldn't touch UI state directly.
- **Always `[weak self]`** in long-lived `Task` closures inside reference types.
- **Cancellation:** check `Task.isCancelled` in long loops; use `try Task.checkCancellation()` in `throws` contexts; cancel parents on dismissal.
- **`AsyncSequence`** beats `NotificationCenter` callbacks for event streams; use `for await event in NotificationCenter.default.notifications(named:)`.
- **`Sendable`** — fix warnings, don't suppress them. Make value types `Sendable`; use `@unchecked Sendable` only with a clear lock or queue.
- **`MainActor.run { … }`** to mutate UI state from a detached context. Don't use `DispatchQueue.main.async` in Swift-Concurrency code.

### Observation (Swift 5.9+)

- `@Observable` replaces `ObservableObject` + `@Published`. No `objectWillChange`; the framework tracks reads.
- Child views write back to an `@Observable` via `@Bindable`, not `@ObservedObject`.
- `@State` is for **local UI state only** (hover, animation toggle). Shared/persistent state lives on the `@Observable` model.

### Generics & protocols

- Protocol-oriented design beats inheritance for value types.
- **Associated types** (`associatedtype`) over generic protocols where the conformer fixes the type.
- **`some Protocol`** (opaque return types) over `any Protocol` when the concrete type is known at the call site — opaque preserves identity and avoids boxing.
- **`any Protocol`** (existentials) when you genuinely need heterogeneous storage.
- **Primary associated types** (`Collection<Int>`) allow opaque/existential composition without `where`.

### Property wrappers & result builders

- Reach for an existing wrapper (`@State`, `@Binding`, `@Bindable`, `@Environment`, `@AppStorage`) before writing one.
- Custom `@propertyWrapper` only when the wrapper is reused across many call sites. Otherwise a computed property is clearer.
- Result builders (`@resultBuilder`) — almost always overkill outside DSLs.

### Memory

- Reference-type capture in closures defaults to **strong**. Use `[weak self]` for long-lived closures (Tasks, observers, completion handlers stored anywhere).
- `unowned` only when you can guarantee the lifetime; otherwise `weak`.
- `weak var delegate: …Delegate?` for classic delegate patterns.

### Codable

- Conform value types to `Codable` for serialisation. Customise via `CodingKeys` enum.
- For polymorphic JSON, prefer a tagged enum + manual `init(from:)`/`encode(to:)` over inheritance.
- Date strategy: pick `.iso8601` unless the API mandates otherwise. Never let the default `.deferredToDate` ship.

### API design

- Names read like English at the call site: `array.remove(at: 0)`, not `array.removeAt(0)`.
- Mutating methods are imperative verbs (`sort()`); non-mutating return value (`sorted()`).
- Argument labels describe the role at the call site; if a label adds no information, use `_`.
- Default access is `internal`; mark `private` aggressively; widen only when used.
- `final` on classes that aren't designed for inheritance — enables devirtualisation and signals intent.

### Testing (swift-testing)

- `import Testing`, `@Test`, `#expect(…)`, `#require(…)`. Decorate suites as `struct`, isolate with `@MainActor` when they touch UI state.
- `throws` on the test function — propagate, don't `try?` inside the test. Failure should surface.
- Parameterise with `@Test(arguments: …)` instead of writing N near-duplicate tests.
- `confirmation { … }` for async event tests. `withKnownIssue { … }` for currently-broken tests instead of disabling them.

## Anti-patterns to flag

- `XCTestCase` / `XCTAssert` in a swift-testing codebase.
- `ObservableObject` / `@Published` next to `@Observable` (mixed paradigms).
- `DispatchQueue.main.async` mixed with `await MainActor.run` in the same module.
- `Task.detached` without `[weak self]`.
- `!` force-unwrap outside `lazy`.
- `do { try x() } catch { }` — silent swallow.
- Inheritance hierarchies on `class` where a `protocol` + value types would do.
- `String`-typed identifiers when an `enum` would catch typos at compile time.

## Deliverable shape

When writing code: match the project's conventions, ship the smallest change, no comments unless the *why* is non-obvious.

When reviewing: cite specific lines, name the idiom violated, give the corrected snippet — no vague advice.
