import Foundation

/// Where AIMP skin work runs off the main thread: a thread with a deep stack, not a dispatch or
/// concurrency thread's 512 KB. A skin's dataflow reads through itself (a page's visibility, the
/// item it holds, the binding that shows it) many levels down, and laying out AIMP Modern v3.63's
/// main form as it loaded ran out of stack there.
final class AIMPSkinWorker: @unchecked Sendable {
    /// The stack each worker thread gets.
    static let stackSize = 16 << 20

    private let lock = NSCondition()
    private var work: [() -> Void] = []
    private var suspensions = 0

    /// A serial worker: what is handed to `async` runs one at a time, in order, on its own thread.
    init(name: String, qos: QualityOfService) {
        let thread = Thread { [unowned self] in self.run() }
        thread.name = name
        thread.qualityOfService = qos
        thread.stackSize = Self.stackSize
        thread.start()
    }

    func async(_ block: @escaping () -> Void) {
        lock.lock()
        work.append(block)
        lock.signal()
        lock.unlock()
    }

    /// Holds back what is handed to `async` until as many `resume`s (as a dispatch queue's).
    func suspend() {
        lock.lock()
        suspensions += 1
        lock.unlock()
    }

    func resume() {
        lock.lock()
        suspensions -= 1
        lock.signal()
        lock.unlock()
    }

    private func run() {
        while true {
            lock.lock()
            while work.isEmpty || suspensions > 0 { lock.wait() }
            let next = work.removeFirst()
            lock.unlock()
            autoreleasepool { next() }
        }
    }

    /// `body` on a thread of its own with the deep stack, its result handed back to the caller.
    static func run<T: Sendable>(qos: QualityOfService = .userInitiated, _ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result(catching: body)) }
            thread.qualityOfService = qos
            thread.stackSize = stackSize
            thread.start()
        }
    }
}
