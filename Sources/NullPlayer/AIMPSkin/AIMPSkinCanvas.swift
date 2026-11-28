import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// What AIMP draws with, on one flipped bitmap context (top-left origin, a skin pixel a point): its
/// pictures filling a rect as each says, upright images, fills, masks, lines of text. The painter
/// decides what goes where (`AIMPSkinPainter`); this only puts it there.
struct AIMPSkinCanvas {
    let context: CGContext
    /// The clock a running line scrolls by, in seconds.
    let clock: Double
    /// The fonts the skin being drawn ships, for every text drawn or measured here.
    var fonts: AIMPSkinFonts.Shelf? = nil

    // MARK: Pictures

    /// A frame filling `rect` as its picture says (`AIMPSkinImage.Fill`): centred at its own size, or
    /// nine-sliced, the margins' corners unscaled, edges and middle stretched (tiled); a picture
    /// with stretch columns keeps all but those two columns their size.
    func paint(_ image: AIMPSkinImage?, in rect: CGRect, frame: Int = 0) {
        guard let image, let source = image.frame(frame), rect.width > 0, rect.height > 0 else { return }
        let m = image.margins
        let sw = source.width, sh = source.height
        if let columns = image.stretchColumns, sw == image.width {
            // Fixed, stretched, fixed, stretched, fixed: each stretched column takes half the change.
            let (l, r) = (columns.left, columns.right), extra = rect.width - CGFloat(sw)
            let widths = [CGFloat(l.lowerBound), CGFloat(l.count) + (extra / 2).rounded(.down), CGFloat(r.lowerBound - l.upperBound),
                          CGFloat(r.count) + extra - (extra / 2).rounded(.down), CGFloat(sw - r.upperBound)]
            let starts = [0, l.lowerBound, l.upperBound, r.lowerBound, r.upperBound]
            let lengths = [l.lowerBound, l.count, r.lowerBound - l.upperBound, r.count, sw - r.upperBound]
            var x = rect.minX
            for i in 0..<5 where lengths[i] > 0 && widths[i] > 0 {
                if let piece = source.cropping(to: CGRect(x: starts[i], y: 0, width: lengths[i], height: sh)) {
                    drawUpright(piece, in: CGRect(x: x, y: rect.minY, width: widths[i], height: rect.height))
                }
                x += widths[i]
            }
            return
        }
        switch image.fill {
        case .center where rect.width >= CGFloat(sw) && rect.height >= CGFloat(sh):
            drawUpright(source, in: CGRect(x: (rect.midX - CGFloat(sw) / 2).rounded(.down), y: (rect.midY - CGFloat(sh) / 2).rounded(.down),
                                           width: CGFloat(sw), height: CGFloat(sh)))
            return
        default:
            break
        }
        let tiled = image.fill == .tile
        guard m != .init(), m.left + m.right <= sw, m.top + m.bottom <= sh else {
            if tiled { tile(source, in: rect) } else { drawUpright(source, in: rect) }
            return
        }
        // A large one is sliced once per picture, size and scale and drawn as made: stretching its
        // middle again every frame cost M5 (a 58-px shadow and a 30-px panel over its window, at 2×)
        // most of its 42 ms a frame.
        let device = context.userSpaceToDeviceSpaceTransform
        let scale = (device.a * device.a + device.b * device.b).squareRoot()
        if rect.width * rect.height > 4_096, scale > 0,
           let sliced = Self.sliced(source, margins: m, tiled: tiled, width: Int((rect.width * scale).rounded()),
                                    height: Int((rect.height * scale).rounded()), scale: scale) {
            drawUpright(sliced, in: rect)
            return
        }
        nineSlice(source, margins: m, tiled: tiled, in: rect)
    }

    /// `source` repeated over `rect` from its top-left: one tiled draw (a 1-px tile over a window is
    /// thousands of draws), upright, the flipped pattern running up from whole tiles below the top.
    private func tile(_ source: CGImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let rows = (rect.height / CGFloat(source.height)).rounded(.up) * CGFloat(source.height)
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY + rows)
        context.scaleBy(x: 1, y: -1)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height), byTiling: true)
        context.restoreGState()
    }

    private struct Sliced: Hashable, Sendable {
        let source: ObjectIdentifier
        let margins: [Int]
        let tiled: Bool
        let width: Int
        let height: Int
        /// The device pixels a skin pixel: one raster at 1× and at 2× has corners of two sizes.
        let scale: CGFloat
    }

    /// Made slicings, each with its source held weakly (`AIMPDerivedImage`).
    private static let slicings = AIMPSkinCache<Sliced, AIMPDerivedImage>(limit: 64, byteLimit: 256 << 20) { $0.image?.aimpCacheBytes ?? 0 }

    /// `source` nine-sliced by `margins` into `width`×`height` device pixels, `scale` of them a skin pixel.
    private static func sliced(_ source: CGImage, margins m: AIMPSkinImage.Margins, tiled: Bool, width: Int, height: Int,
                               scale: CGFloat) -> CGImage? {
        guard width > 0, height > 0, width * height <= 16_000_000 else { return nil }
        let key = Sliced(source: ObjectIdentifier(source), margins: [m.left, m.top, m.right, m.bottom], tiled: tiled,
                         width: width, height: height, scale: scale)
        return slicings.value(key, isValid: { $0.isMade(from: source) }) {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return AIMPDerivedImage(source: source, image: nil) }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            AIMPSkinCanvas(context: context, clock: 0)
                .nineSlice(source, margins: m, tiled: tiled, in: CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale))
            return AIMPDerivedImage(source: source, image: context.makeImage())
        }.image
    }

    /// `source`'s corners unscaled, its edges and middle stretched over `rect`, or repeated when it
    /// tiles: AIMP keeps a tiled picture's margins too (Terran's 616-px window frame over its 660-px
    /// window, its right corners at the right edge, not a second left edge past a cut-off first copy).
    private func nineSlice(_ source: CGImage, margins m: AIMPSkinImage.Margins, tiled: Bool = false, in rect: CGRect) {
        let sw = source.width, sh = source.height
        let xs = [(0, m.left, rect.minX, rect.minX + CGFloat(m.left)),
                  (m.left, sw - m.right, rect.minX + CGFloat(m.left), rect.maxX - CGFloat(m.right)),
                  (sw - m.right, sw, rect.maxX - CGFloat(m.right), rect.maxX)]
        let ys = [(0, m.top, rect.minY, rect.minY + CGFloat(m.top)),
                  (m.top, sh - m.bottom, rect.minY + CGFloat(m.top), rect.maxY - CGFloat(m.bottom)),
                  (sh - m.bottom, sh, rect.maxY - CGFloat(m.bottom), rect.maxY)]
        for (sx0, sx1, dx0, dx1) in xs where sx1 > sx0 && dx1 > dx0 {
            for (sy0, sy1, dy0, dy1) in ys where sy1 > sy0 && dy1 > dy0 {
                if let piece = source.cropping(to: CGRect(x: sx0, y: sy0, width: sx1 - sx0, height: sy1 - sy0)) {
                    let into = CGRect(x: dx0, y: dy0, width: dx1 - dx0, height: dy1 - dy0)
                    if tiled { tile(piece, in: into) } else { drawUpright(piece, in: into) }
                }
            }
        }
    }

    /// Where `paint` puts `image` in `rect`: the middle at its own size for a centred picture.
    static func drawnRect(_ image: AIMPSkinImage, in rect: CGRect) -> CGRect {
        let frame = image.frameSize
        guard image.fill == .center, rect.width >= frame.width, rect.height >= frame.height else { return rect }
        return CGRect(x: (rect.midX - frame.width / 2).rounded(.down), y: (rect.midY - frame.height / 2).rounded(.down),
                      width: frame.width, height: frame.height)
    }

    /// An image upright in the flipped context.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// `rect` filled with an ARGB colour; a clear one fills nothing.
    func fill(_ rect: CGRect, argb: UInt32?) {
        guard let argb, argb >> 24 != 0 else { return }
        context.setFillColor(AIMPSkinText.color(argb))
        context.fill(rect)
    }

    // MARK: Masks

    /// Clips to `mask` (a grayscale image the size of `rect`) over `rect`, inside a saved state the
    /// caller restores. A CGContext mask is upside down in this flipped context, so it is clipped
    /// through a flip and flipped back.
    func clip(to rect: CGRect, mask: CGImage) {
        context.translateBy(x: 0, y: rect.minY * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: rect, mask: mask)
        context.translateBy(x: 0, y: rect.minY * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
    }

    /// A picture's alpha as a grayscale mask, which `clip(to:mask:)` needs (a skin's mask frame is
    /// a coloured shape on transparency).
    static func grayMask(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let alpha = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        alpha.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = alpha.data else { return nil }
        let data = Data(bytes: bytes, count: width * height) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Frame `frame` of `picture` filled into `size` as the picture fills, as a grayscale mask; made
    /// once per frame and size (`AIMPSkinImage.mask`).
    static func mask(_ picture: AIMPSkinImage, frame: Int, size: CGSize) -> CGImage? {
        picture.mask(frame: frame, width: Int(size.width), height: Int(size.height)) {
            guard let shape = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            shape.translateBy(x: 0, y: size.height)
            shape.scaleBy(x: 1, y: -1)
            AIMPSkinCanvas(context: shape, clock: 0).paint(picture, in: CGRect(origin: .zero, size: size), frame: frame)
            return shape.makeImage().flatMap(grayMask)
        }
    }

    /// Frame `frame` of `picture` at its own size as a grayscale mask, made once (a cover display's
    /// round label, stretched over its rect by the clip).
    static func mask(_ picture: AIMPSkinImage, frame: Int) -> CGImage? {
        // Size 0 keys the frame as drawn, apart from the sizes `mask(_:frame:size:)` fills.
        picture.mask(frame: frame, width: 0, height: 0) { picture.frame(frame).flatMap(grayMask) }
    }

    // MARK: Blur

    /// What the canvas holds so far inside `pixels` (whole pixels, top-left origin), copied out of
    /// its rows rather than imaging the whole window for each pane of glass.
    func drawnSoFar(in pixels: CGRect) -> CGImage? {
        guard let base = context.data, let space = context.colorSpace else { return nil }
        let row = context.bytesPerRow, top = Int(pixels.minY), rows = Int(pixels.height)
        guard let provider = CGDataProvider(data: Data(bytes: base + top * row, count: rows * row) as CFData) else { return nil }
        return CGImage(width: context.width, height: rows, bitsPerComponent: context.bitsPerComponent, bitsPerPixel: context.bitsPerPixel,
                       bytesPerRow: row, space: space, bitmapInfo: context.bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)?
            .cropping(to: CGRect(x: Int(pixels.minX), y: 0, width: Int(pixels.width), height: rows))
    }

    /// `image` blurred by an AIMP `BlurLevel` (0–100): a Gaussian blur, edges held, `BlurLevel` 100 a
    /// 25-px sigma, a wash of the picture's colours (W10's glass over the cover behind its icon bar;
    /// shrinking and stretching showed blocks). Nil for no blur.
    static func blurred(_ image: CGImage, level: Double) -> CGImage? {
        guard level > 0 else { return nil }
        let source = CIImage(cgImage: image)
        let soft = source.clampedToExtent().applyingGaussianBlur(sigma: level / 4).cropped(to: source.extent)
        return blurContext.createCGImage(soft, from: source.extent)
    }

    /// One Core Image context for every blur (making one is costly; it is safe across threads).
    static let blurContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Text

    /// How wide `text` draws in `font` (`AIMPSkinText.width`).
    func width(_ text: String, font: AIMPSkinFont) -> CGFloat { AIMPSkinText.width(text, font: font, shelf: fonts) }

    /// `text` in lines no wider than `width` (`AIMPSkinText.lines`).
    func lines(_ text: String, font: AIMPSkinFont, width: CGFloat) -> [CTLine] {
        AIMPSkinText.lines(text, font: font, width: width, shelf: fonts)
    }

    /// Wrapped `lines` down from the top of `rect`, each placed by `alignment` (none: left), clipped to it.
    func draw(_ lines: [CTLine], font: AIMPSkinFont, in rect: CGRect, alignment: AIMPSkinTextAlign?) {
        let ascent = CTFontGetAscent(font.ctFont(on: fonts)), height = AIMPSkinText.lineHeight(font, shelf: fonts)
        context.saveGState()
        context.clip(to: rect)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (i, line) in lines.enumerated() {
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x = alignment == .center ? rect.midX - width / 2 : alignment == .right ? rect.maxX - width : rect.minX
            context.textPosition = CGPoint(x: x, y: rect.minY + CGFloat(i) * height + ascent)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    /// One line, vertically centred on `at.y`; `Segoe UI` and other Windows faces fall back to the
    /// system font. Centred in `box` when given; right-aligned 4 px inside `clip` (less where it would not fit); a line that
    /// `scrolls` and is too long for `clip` runs leftward at 30 px a second, the next pass a gap behind.
    func draw(_ text: String, font: AIMPSkinFont, at point: CGPoint, centeredIn box: CGRect?, clippedTo clip: CGRect? = nil,
              scrolls: Bool = false, rightAligned: Bool = false) {
        let ctFont = font.ctFont(on: fonts)
        let line = CTLineCreateWithAttributedString(AIMPSkinText.styled(text, font: font, shelf: fonts))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        var x = box.map { $0.midX - CGFloat(width) / 2 } ?? point.x
        // Text that only just fits takes the inset rather than running out of the left edge (AIMP
        // Modern v3.63's "Search :", 40 px in a 40-px label, lost its S).
        if rightAligned, let clip { x = max(clip.minX, clip.maxX - 4 - CGFloat(width)) }
        let baseline = point.y + (CTFontGetAscent(ctFont) - CTFontGetDescent(ctFont)) / 2
        context.saveGState()
        if let clip { context.clip(to: clip) }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        var passes = [x]
        if scrolls, let clip, CGFloat(width) > clip.maxX - x {
            let lap = CGFloat(width) + 40
            x -= CGFloat((clock * 30).truncatingRemainder(dividingBy: Double(lap)))
            passes = [x, x + lap]
        }
        for start in passes {
            context.textPosition = CGPoint(x: start, y: baseline)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
