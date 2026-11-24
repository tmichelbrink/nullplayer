import CoreGraphics
import Foundation
import os

/// Values a skin makes once and draws many times (a blurred cover, a key's mask, a restyled
/// control), kept behind a lock: frames are laid out and drawn off the main thread, every window's
/// on the same skin. A value is made outside the lock, so a window drawing beside the one making it
/// waits only for a lookup, never for a blur; two that both miss both make it, and the first stored
/// is kept (as `AIMPSkinPixels` decodes). At most `limit` are kept, and no more than `byteLimit` of
/// them, the oldest stored let go first.
final class AIMPSkinCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let limit: Int
    /// The most bytes kept, by `cost`: a few big rasters (a large window's slicings at 2×, ~55 MiB
    /// each) would otherwise pass any sensible memory use well within `limit` entries.
    private let byteLimit: Int
    private let cost: @Sendable (Value) -> Int
    private let stored = OSAllocatedUnfairLock(initialState: Stored())

    private struct Stored: Sendable {
        var values: [Key: Value] = [:]
        var costs: [Key: Int] = [:]
        var bytes = 0
        /// Keys in the order they were stored, the next to let go first.
        var order: [Key] = []
    }

    init(limit: Int, byteLimit: Int = .max, cost: @escaping @Sendable (Value) -> Int = { _ in 0 }) {
        self.limit = max(1, limit)
        self.byteLimit = byteLimit
        self.cost = cost
    }

    /// The value for `key`, as `make` makes it, made once while it is kept. One costing more than
    /// the whole `byteLimit` is handed back without being kept. A kept value `isValid` refuses (one
    /// whose source is gone) is made again and replaced.
    func value(_ key: Key, isValid: (Value) -> Bool = { _ in true }, making make: () -> Value) -> Value {
        if let found = stored.withLock({ $0.values[key] }), isValid(found) { return found }
        let made = make()
        let bytes = cost(made)
        guard bytes <= byteLimit else { return made }
        return stored.withLock { [limit, byteLimit] stored in
            if let found = stored.values[key], isValid(found) { return found }
            if stored.values[key] != nil {
                stored.bytes -= stored.costs.removeValue(forKey: key) ?? 0
                stored.order.removeAll { $0 == key }
            }
            stored.values[key] = made
            stored.costs[key] = bytes
            stored.bytes += bytes
            stored.order.append(key)
            while stored.order.count > limit || stored.bytes > byteLimit {
                let oldest = stored.order.removeFirst()
                stored.values[oldest] = nil
                stored.bytes -= stored.costs.removeValue(forKey: oldest) ?? 0
            }
            return made
        }
    }

    /// How many values are kept.
    var count: Int { stored.withLock { $0.values.count } }
}

extension CGImage {
    /// The raster's bytes, as an `AIMPSkinCache`'s `cost` counts them.
    var aimpCacheBytes: Int { bytesPerRow * height }
}
