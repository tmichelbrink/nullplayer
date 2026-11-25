import CoreGraphics
import Foundation

/// The decoded pixels of one skin's pictures, never more than `limit` at once
/// (`AIMPSkinPolicy.decodedPixels`). A picture decodes when it is first drawn, not as the skin
/// loads: the photo-realistic decks carry up to four times the budget in pictures (Mayak-203's
/// alternative reels, one set shown at a time), of which a window draws a fraction. When a decode
/// would pass the budget, the pictures drawn longest ago are let go, to decode again if drawn again.
///
/// One lock for all of a skin's pictures: a skin loads and measures its forms off the main thread
/// and draws on a background queue, and a decode must not race the eviction it causes. Unchecked,
/// unlike the skin's other caches (each a value behind its own `OSAllocatedUnfairLock`): this lock
/// guards state spread over every `AIMPSkinPixels` of the skin (a decode evicts other pictures),
/// which no lock owning one value can hold.
final class AIMPSkinPixelBudget: @unchecked Sendable {
    let limit: Int
    private let lock = NSLock()
    private var resident = 0
    private var clock = 0
    private var decoded: [ObjectIdentifier: Resident] = [:]

    private struct Resident {
        weak var pixels: AIMPSkinPixels?
        let count: Int
    }

    init(limit: Int = AIMPSkinPolicy.decodedPixels) {
        self.limit = limit
    }

    /// The pixels decoded and not let go.
    var residentPixels: Int { lock.withLock { resident } }

    fileprivate func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    /// A tick of the clock that orders pictures by when they were last drawn. Under the lock.
    fileprivate func tick() -> Int {
        clock += 1
        return clock
    }

    /// Room for `count` pixels of `pixels`, letting the least recently drawn others go first.
    /// Under the lock.
    fileprivate func admit(_ pixels: AIMPSkinPixels, count: Int) {
        while resident + count > limit {
            guard let (id, oldest) = decoded.filter({ $0.key != ObjectIdentifier(pixels) })
                .min(by: { ($0.value.pixels?.lastUse ?? 0) < ($1.value.pixels?.lastUse ?? 0) }) else { break }
            oldest.pixels?.evict()
            resident -= oldest.count
            decoded[id] = nil
        }
        resident += count
        decoded[ObjectIdentifier(pixels)] = Resident(pixels: pixels, count: count)
    }
}

/// One picture's pixels, decoded on demand within its skin's `AIMPSkinPixelBudget` and cut into
/// frames: premultiplied BGRA, top row first, `frameCount` frames side by side or stacked.
/// Unchecked: its mutable state is under its budget's lock (`AIMPSkinPixelBudget`). The lock is
/// held only to look up, admit or let go of a decode, never while decoding: a picture decodes on
/// the thread that first draws it, and the window drawing beside it is not held up.
final class AIMPSkinPixels: @unchecked Sendable {
    /// Where a picture's pixels come from: the whole strip's premultiplied BGRA, top row first,
    /// `width × height × 4` bytes or more, decoded within `budget`.
    struct Source {
        let budget: AIMPSkinPixelBudget
        let decode: () throws -> Data
    }

    let width: Int
    let height: Int
    let frameCount: Int
    let stacked: Bool
    let source: Source
    private var budget: AIMPSkinPixelBudget { source.budget }

    // Under the budget's lock.
    fileprivate var lastUse = 0
    private var strip: Strip?
    private var failed = false
    private var measured: Flags?

    /// What `flags` reads from the frames.
    struct Flags {
        let firstFrameBlank: Bool
        let lastFrameFlat: Bool
        let lastFrameBlank: Bool
        let lastFrameGrey: Bool
    }

    init(width: Int, height: Int, frameCount: Int, stacked: Bool, source: Source) {
        self.width = width
        self.height = height
        self.frameCount = frameCount
        self.stacked = stacked
        self.source = source
    }

    /// One frame, decoding the picture if it is not resident; nil when it does not decode.
    func frame(_ index: Int) -> CGImage? { residentStrip()?.frame(index) }

    /// Whether the first of several frames draws nothing, and whether the last is one flat colour
    /// or draws nothing, read from the decoded frames the first time it is asked and kept after (the decode itself
    /// can be let go of); nil when the picture does not decode. Asked as the picture is first laid
    /// out, not as the skin loads: a deck's hundreds of megabytes of pictures do not all decode
    /// before its first frame.
    func flags() -> Flags? {
        if let known = budget.locked({ measured }) { return known }
        guard let strip = residentStrip() else { return nil }
        let found = Flags(firstFrameBlank: strip.blank(0), lastFrameFlat: strip.lastFrameFlat, lastFrameBlank: strip.blank(strip.count - 1),
                          lastFrameGrey: strip.lastFrameGrey)
        budget.locked { measured = found }
        return found
    }

    /// Let go of the decoded pixels. Under the budget's lock.
    fileprivate func evict() { strip = nil }

    /// The decoded strip: resident, or decoded now outside the lock and admitted. Two threads that
    /// both find it missing both decode it; the first to admit its decode wins.
    private func residentStrip() -> Strip? {
        let (resident, gaveUp) = budget.locked { () -> (Strip?, Bool) in
            lastUse = budget.tick()
            return (strip, failed)
        }
        if let resident { return resident }
        guard !gaveUp else { return nil }
        let made = (try? source.decode()).flatMap { pixels in
            pixels.count >= width * height * 4 ? Strip(pixels, width: width, height: height, frames: frameCount, stacked: stacked) : nil
        }
        return budget.locked {
            if let strip { return strip }
            guard let made else {
                failed = true
                return nil
            }
            budget.admit(self, count: width * height)
            strip = made
            return made
        }
    }

    /// The decoded frames, one after another in one buffer (a side-by-side strip is repacked), each
    /// handed out as a picture of its own over its bytes. A frame cropped from the strip made Core
    /// Graphics copy it out of the whole strip again at every draw, 30 times a second for each
    /// reel, meter and lamp: the most of a playing deck's drawing time (GX-77 Grey).
    private final class Strip: @unchecked Sendable {
        let bytes: CFData
        let frameWidth: Int
        let frameHeight: Int
        let count: Int
        /// Each frame as a picture over its bytes, made with the strip: the strip never changes
        /// after, so a frame is read from any thread without a lock.
        private var views: [CGImage?] = []

        init(_ pixels: Data, width: Int, height: Int, frames: Int, stacked: Bool) {
            let frameWidth = stacked ? width : width / frames, frameHeight = stacked ? height / frames : height
            count = frames
            self.frameWidth = frameWidth
            self.frameHeight = frameHeight
            let frameBytes = frameWidth * frameHeight * 4
            if stacked || frames == 1 {
                bytes = (pixels.count == width * height * 4 ? pixels : pixels.prefix(width * height * 4)) as CFData
            } else {
                var packed = Data(count: frameBytes * frames)
                packed.withUnsafeMutableBytes { out in
                    pixels.withUnsafeBytes { strip in
                        guard let to = out.baseAddress, let from = strip.baseAddress, frameBytes > 0 else { return }
                        for frame in 0..<frames {
                            for row in 0..<frameHeight {
                                memcpy(to + frame * frameBytes + row * frameWidth * 4,
                                       from + (row * width + frame * frameWidth) * 4, frameWidth * 4)
                            }
                        }
                    }
                }
                bytes = packed as CFData
            }
            // A header claiming more frames than the strip has pixels across (u32 frame counts) cuts
            // frames of no size, which draw nothing: none are made, rather than billions of nils.
            views = frameWidth > 0 && frameHeight > 0 ? (0..<frames).map(view) : []
        }

        /// Frame `index`, clamped to the last; nil when the frames have no size.
        func frame(_ index: Int) -> CGImage? { views.isEmpty ? nil : views[min(max(index, 0), views.count - 1)] }

        private func view(_ i: Int) -> CGImage? {
            guard frameWidth > 0, frameHeight > 0 else { return nil }
            let length = frameWidth * frameHeight * 4
            guard let base = CFDataGetBytePtr(bytes) else { return nil }
            let owner = Unmanaged.passRetained(bytes).toOpaque()
            guard let provider = CGDataProvider(dataInfo: owner, data: base + i * length, size: length,
                                                releaseData: { owner, _, _ in Unmanaged<CFData>.fromOpaque(owner!).release() })
            else {
                Unmanaged<CFData>.fromOpaque(owner).release()
                return nil
            }
            // BGRA in memory is ARGB read little-endian.
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            return CGImage(width: frameWidth, height: frameHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: frameWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info,
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }

        /// Nothing drawn in frame `index` of several.
        func blank(_ index: Int) -> Bool {
            guard count > 1 else { return false }
            return withFrame(index) { bytes in
                !stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] != 0 }
            }
        }

        /// The last of several frames one colour (within 8 a channel) wherever it is opaque, over
        /// more than 16 pixels.
        var lastFrameFlat: Bool {
            guard count > 1 else { return false }
            return withFrame(count - 1) { bytes in
                var colour: (Int, Int, Int)?
                var drawn = 0
                for at in stride(from: 0, to: bytes.count, by: 4) where bytes[at + 3] == 255 {
                    let here = (Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2]))
                    if let colour, abs(colour.0 - here.0) > 8 || abs(colour.1 - here.1) > 8 || abs(colour.2 - here.2) > 8 {
                        return false
                    }
                    colour = colour ?? here
                    drawn += 1
                }
                return drawn > 16
            }
        }

        /// The last of several frames grey wherever it is opaque (each channel within 12 of the
        /// others): a mask, grey by angle, rather than one more picture of the control.
        var lastFrameGrey: Bool {
            guard count > 1 else { return false }
            return withFrame(count - 1) { bytes in
                for at in stride(from: 0, to: bytes.count, by: 4) where bytes[at + 3] > 0 {
                    let (a, b, c) = (Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2]))
                    if abs(a - b) > 12 || abs(b - c) > 12 || abs(a - c) > 12 { return false }
                }
                return true
            }
        }

        /// Frame `index`'s bytes, in place.
        private func withFrame(_ index: Int, _ body: (UnsafeBufferPointer<UInt8>) -> Bool) -> Bool {
            let length = frameWidth * frameHeight * 4
            guard length > 0, let base = CFDataGetBytePtr(bytes) else { return false }
            return body(UnsafeBufferPointer(start: base + index * length, count: length))
        }
    }
}
