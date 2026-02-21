import Foundation
import Combine

/// Thread-safe wrapper around `Set<AnyCancellable>`.
///
/// Actors cannot store a mutable `var Set<AnyCancellable>` that is mutated
/// from `nonisolated` methods. `CancellableBag` wraps the set in a `class`
/// (reference type), making it safe to store as an actor `let` constant
/// while still being mutated via `store(_:)` from any isolation context.
final class CancellableBag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellables = Set<AnyCancellable>()

    /// Retain a cancellable in the bag. Thread-safe.
    func store(_ cancellable: AnyCancellable) {
        lock.lock(); defer { lock.unlock() }
        cancellables.insert(cancellable)
    }

    /// Cancel and discard all retained subscriptions.
    func cancelAll() {
        lock.lock(); defer { lock.unlock() }
        cancellables.removeAll()
    }
}
