import CoreGraphics
import Foundation

/// A picture's pixels, read once as the frame is drawn (off main), so a hit test on main reads one
/// byte of them rather than copying the picture.
struct AIMPAlphaMask: Equatable, Sendable {
    let width: Int
    let height: Int
    private let pixels: Data
    private let bytesPerRow: Int
    /// Where alpha sits in a pixel: first of ARGB or last of RGBA, in memory order.
    private let offset: Int

    /// Nil for a picture that is not 32 bits a pixel (hit as its whole rect).
    init?(_ image: CGImage?) {
        guard let image, image.bitsPerPixel == 32, let data = image.dataProvider?.data else { return nil }
        // Alpha is the first byte of ARGB, or the last; little-endian swaps the order in memory.
        let alphaFirst = [CGImageAlphaInfo.premultipliedFirst, .first].contains(image.alphaInfo)
        offset = alphaFirst != image.bitmapInfo.contains(.byteOrder32Little) ? 0 : 3
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        pixels = data as Data
    }

    func covers(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let at = y * bytesPerRow + x * 4 + offset
        return at < pixels.count && pixels[pixels.startIndex + at] > 0
    }

    /// The bounding box of every pixel with any alpha, nil when nothing is drawn: the part of a
    /// frame a window shows (`AIMPSkinMainView.contentRect`). Measured inward from the edges, so a
    /// solid deck costs a row and a column rather than every pixel: it runs whenever a counter or
    /// page changes, which some skins do every tick (Sony TC-RX80's reels).
    var drawnBounds: CGRect? {
        pixels.withUnsafeBytes { raw -> CGRect? in
            let bytes = raw.bindMemory(to: UInt8.self)
            func drawn(_ x: Int, _ y: Int) -> Bool {
                let at = y * bytesPerRow + x * 4 + offset
                return at < bytes.count && bytes[at] > 0
            }
            func rowDrawn(_ y: Int) -> Bool { (0..<width).contains { drawn($0, y) } }
            guard let minY = (0..<height).first(where: rowDrawn),
                  let maxY = (minY..<height).reversed().first(where: rowDrawn) else { return nil }
            var minX = width, maxX = -1
            for y in minY...maxY {
                // Only the columns outside what is already known can widen the box.
                if let x = (0..<minX).first(where: { drawn($0, y) }) { minX = x }
                if let x = (max(maxX + 1, minX)..<width).reversed().first(where: { drawn($0, y) }) { maxX = x }
            }
            guard maxX >= minX else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }
}
