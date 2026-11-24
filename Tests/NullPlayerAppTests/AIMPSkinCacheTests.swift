import CoreGraphics
import XCTest
@testable import NullPlayer

/// `AIMPSkinCache`'s check on a kept value, which the canvas's slicings rely on to hold their source
/// weakly: a value whose source is gone is made again, not handed back.
final class AIMPSkinCacheTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        weak var source: CGImage?
        let made: Int
        init(source: CGImage, made: Int) { (self.source, self.made) = (source, made) }
    }

    private static func image() -> CGImage? {
        CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    func testAValueWhoseSourceIsGoneIsMadeAgain() throws {
        let cache = AIMPSkinCache<Int, Box>(limit: 4)
        var makes = 0
        var source: CGImage? = try XCTUnwrap(Self.image())
        let first = cache.value(1, isValid: { $0.source === source }) { makes += 1; return Box(source: source!, made: makes) }
        XCTAssertEqual(cache.value(1, isValid: { $0.source === source }) { makes += 1; return Box(source: source!, made: makes) }.made,
                       first.made, "kept while its source lives")
        source = nil
        XCTAssertNil(first.source, "the cache does not keep the source alive")
        let other = try XCTUnwrap(Self.image())
        let again = cache.value(1, isValid: { $0.source === other }) { makes += 1; return Box(source: other, made: makes) }
        XCTAssertEqual(again.made, 2, "made again for another source")
        XCTAssertEqual(cache.count, 1)
    }
}
