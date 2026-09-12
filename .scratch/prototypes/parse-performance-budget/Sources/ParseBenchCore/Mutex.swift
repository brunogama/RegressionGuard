import Foundation

/// Minimal mutual exclusion, so the counter is `Sendable` without an actor.
///
/// An actor would make every call site `await`, and an `await` inside a timed region is exactly
/// the kind of measurement artefact the harness must not introduce.
final class Mutex<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSLock()

  init(_ value: Value) { self.value = value }

  func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}
