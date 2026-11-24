import CoreGraphics
import Foundation

/// What a skin shows of the player beyond its pictures: the equalizer curve, cover art, frosted
/// glass, the oscilloscope and the spectrum.
extension AIMPSkinPainter {
    /// An `EqualizerDisplay`: its panel, the preamp level as a line and the bands as a smooth
    /// curve, ±12 dB over the height, in the skin's `ColorPreamp` and `ColorCurve`.
    func drawEqualizer(preamp: UInt32?, curve: UInt32?, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let inner = rect.insetBy(dx: 2, dy: 2)
        func y(_ value: Double) -> CGFloat { inner.midY - CGFloat(value * 2 - 1) * inner.height / 2 }
        if let preamp {
            context.setStrokeColor(AIMPSkinText.color(preamp))
            context.setLineWidth(1)
            context.strokeLineSegments(between: [CGPoint(x: inner.minX, y: y(host.player.preamp)), CGPoint(x: inner.maxX, y: y(host.player.preamp))])
        }
        let gains = host.player.eqGains
        guard let curve, gains.count > 1 else { return }
        let points = gains.enumerated().map { i, gain in
            CGPoint(x: inner.minX + inner.width * CGFloat(i) / CGFloat(gains.count - 1), y: y(gain))
        }
        // Catmull–Rom through the bands, as a Bézier path.
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        context.saveGState()
        context.clip(to: rect)
        context.addPath(path)
        context.setStrokeColor(AIMPSkinText.color(curve))
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }

    /// A `CoverArtDisplay`: the playing track's artwork filling its rect, inside the skin's mask
    /// frame (`MaskFrame`: SL-1200's round record label), with the skin's own picture over it: its
    /// `CoverFrame` where it names one (RealPlayer 11's gloss; its frame 0 is "no cover"), else frame 0.
    /// Without artwork the skin's label shows, or the "no cover" frame of a skin that names a `CoverFrame`.
    func drawCoverArt(_ cover: AIMPControlClass.Cover, mask maskFrame: Int?, image: AIMPSkinImage?, in rect: CGRect) {
        guard let artwork = host.player.coverArt else {
            if cover.coverFrame != nil { paint(image, in: rect, frame: 0) }
            return
        }
        context.saveGState()
        if let maskFrame, let image, let mask = AIMPSkinCanvas.mask(image, frame: maskFrame) {
            canvas.clip(to: rect, mask: mask)
        }
        // `BlurLevel` blurs it (Soot's backdrop behind its player pane), once per cover and level.
        let art = cover.blur.flatMap { level in
            flow.skin.blurredCovers.image(artwork, level: level) { AIMPSkinCanvas.blurred(artwork, level: level) }
        } ?? artwork
        // Fill: the shorter side fits, the longer is cropped.
        let scale = max(rect.width / CGFloat(art.width), rect.height / CGFloat(art.height))
        let size = CGSize(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale)
        let drawn = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        // Cropped to its box: W10's 136×604 strip behind its icon bar spilled a 604-px cover over the page.
        context.clip(to: rect)
        context.translateBy(x: 0, y: drawn.minY * 2 + drawn.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(art, in: drawn)
        context.restoreGState()
        if let coverFrame = cover.coverFrame {
            paint(image, in: rect, frame: coverFrame)
        } else if let maskFrame, maskFrame != 0 {
            paint(image, in: rect, frame: 0)
        }
    }

    /// A `BlurredGlass`: what is drawn under it so far, blurred by `BlurLevel` (0–100), inside its
    /// skin's mask frame (`MaskFrame`: Soot's round 50-px key backs), tinted by its `Color`.
    func drawBlurredGlass(blur: Double?, tint: AIMPSkinColor?, mask maskFrame: Int?, image: AIMPSkinImage?, in rect: CGRect) {
        // The canvas holds device pixels: a frame drawn at the screen's resolution has `scale` of
        // them per skin pixel. The backdrop is read, and blurred as far, in those.
        let scale = abs(context.ctm.a)
        let device = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let pixels = device.intersection(CGRect(x: 0, y: 0, width: context.width, height: context.height)).integral
        guard pixels.width > 1, pixels.height > 1, let backdrop = canvas.drawnSoFar(in: pixels) else { return }
        let glass = AIMPSkinCanvas.blurred(backdrop, level: (blur ?? 50) * scale) ?? backdrop
        let drawn = CGRect(x: pixels.minX / scale, y: pixels.minY / scale, width: pixels.width / scale, height: pixels.height / scale)
        // The mask frame names where the glass is; a picture without one is the shape itself.
        context.saveGState()
        context.clip(to: image.map { AIMPSkinCanvas.drawnRect($0, in: rect) } ?? rect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        canvas.drawUpright(glass, in: drawn)
        if let image, image.hasPixels {
            context.setBlendMode(.destinationIn)
            paint(image, in: rect, frame: maskFrame ?? 0)
        }
        if let tint = argb(tint), tint >> 24 != 0 {
            context.setBlendMode(.sourceAtop)
            canvas.fill(rect, argb: tint)
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Analog VU meters for the visualization screen's VU mode, laid out as AIMP 2.6's: two white
    /// faces side by side across the whole box, "VU" in their top corners, an arc of ticks from −20 to
    /// +3 with a red arc over 0…+3, and a black needle from a grey cap at the bottom. AIMP draws its
    /// own from art built into AIMP, which no skin carries; these are drawn here, at a meter's own
    /// shape: each face no taller than `faceAspect` lets it, centred in the box (Bento's 122x99 cover
    /// box stretched its faces to 60x99, the arc a sliver at the bottom).
    func drawMeters(in rect: CGRect, id: AIMPSkinControl.ID) {
        let playing = host.player.playState == .playing
        let gap: CGFloat = 2
        let width = (rect.width - gap) / 2
        let height = min(rect.height, (width / Self.faceAspect).rounded())
        let top = (rect.midY - height / 2).rounded()
        for (index, level) in [host.feedback.levelL, host.feedback.levelR].enumerated() {
            let face = CGRect(x: rect.minX + CGFloat(index) * (width + gap), y: top, width: width, height: height)
            let needle = playing ? host.feedback.gaugeLevels[id.meter(index)] ?? Self.needle(level: level) : 0
            drawMeter(in: face, needle: needle)
        }
    }

    /// A VU face's width over its height: wider than tall, as a meter's face is.
    static let faceAspect: CGFloat = 4.0 / 3.0

    /// Where a VU needle stands for an output `level`, 0 (−20 dB and below) to 1 (+3 dB). A real VU's
    /// scale is even in voltage, so −20…0 dB take most of the arc; 0 dB is a level of about 0.7.
    static func needle(level: Double) -> Double {
        let db = min(3, max(-20, 20 * log10(max(level, 0.0001) / 0.7)))
        return meterFraction(db)
    }

    private static func meterFraction(_ db: Double) -> Double {
        let low = pow(10, -20.0 / 20), high = pow(10, 3.0 / 20)
        return (pow(10, db / 20) - low) / (high - low)
    }

    /// One VU face, its needle at `needle` (0–1 along the arc).
    private func drawMeter(in face: CGRect, needle: Double) {
        guard face.width > 8, face.height > 8 else { return }
        let ink = CGColor(gray: 0.15, alpha: 1), red = CGColor(red: 0.72, green: 0.16, blue: 0.12, alpha: 1)
        context.saveGState()
        context.clip(to: face)
        // AIMP's faces are a soft light grey, a touch darker toward the bottom, not paper white.
        let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [CGColor(gray: 0.89, alpha: 1), CGColor(gray: 0.78, alpha: 1)] as CFArray,
                               locations: [0, 1])
        if let shade {
            context.drawLinearGradient(shade, start: CGPoint(x: face.midX, y: face.minY),
                                       end: CGPoint(x: face.midX, y: face.maxY), options: [])
        }
        context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
        context.setLineWidth(1)
        context.stroke(face.insetBy(dx: 0.5, dy: 0.5))

        // The needle's pivot sits below the face; the arc spans 92° about straight up.
        let radius = min(face.width * 0.50, face.height * 1.05)
        let pivot = CGPoint(x: face.midX, y: face.maxY + radius * 0.08)
        let sweep = 46.0 * Double.pi / 180
        func fraction(_ db: Double) -> Double { Self.meterFraction(db) }
        func point(_ t: Double, _ r: CGFloat) -> CGPoint {
            let angle = -sweep + 2 * sweep * min(1, max(0, t))
            return CGPoint(x: pivot.x + CGFloat(sin(angle)) * r, y: pivot.y - CGFloat(cos(angle)) * r)
        }
        let scale = radius * 0.80
        // The arc and its red end.
        let arc = CGMutablePath()
        for step in 0...40 { let p = point(Double(step) / 40, scale); step == 0 ? arc.move(to: p) : arc.addLine(to: p) }
        context.addPath(arc)
        context.setStrokeColor(ink)
        context.setLineWidth(max(0.6, face.height / 70))
        context.strokePath()
        let hot = CGMutablePath()
        for step in 0...12 {
            let p = point(fraction(0) + (1 - fraction(0)) * Double(step) / 12, scale + max(1.5, face.height / 30))
            step == 0 ? hot.move(to: p) : hot.addLine(to: p)
        }
        context.addPath(hot)
        context.setStrokeColor(red)
        context.setLineWidth(max(1.5, face.height / 18))
        context.strokePath()
        // Ticks and their labels.
        let font = AIMPSkinFont(name: "Tahoma", height: Int(max(5, (face.height * 0.11).rounded())), bold: false, color: 0xFF26_2626)
        let tick = max(2, face.height / 16)
        for db in [-20.0, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3] {
            let t = fraction(db)
            context.move(to: point(t, scale))
            context.addLine(to: point(t, scale + tick))
            context.setStrokeColor(db > 0 ? red : ink)
            context.setLineWidth(max(0.6, face.height / 70))
            context.strokePath()
            // Every mark is labelled on a big face; a small one keeps −20, −10, −5, 0 and +3 apart.
            let labelled: Set<Double> = face.width >= 120 ? [-20, -10, -7, -5, -3, -2, 0, 2, 3] : [-20, -10, -5, 0, 3]
            guard face.height >= 30, labelled.contains(db) else { continue }
            let label = point(t, scale + tick + CGFloat(font.height) * 0.9)
            canvas.draw(db > 0 ? "+\(Int(db))" : "\(Int(db))", font: font, at: label,
                        centeredIn: CGRect(x: label.x - 20, y: label.y - 4, width: 40, height: 8))
        }
        canvas.draw("VU", font: font, at: CGPoint(x: face.minX + 4, y: face.minY + CGFloat(font.height) * 0.8), centeredIn: nil)
        let right = face.maxX - 4 - AIMPSkinText.width("VU", font: font)
        canvas.draw("VU", font: font, at: CGPoint(x: right, y: face.minY + CGFloat(font.height) * 0.8), centeredIn: nil)

        // The needle, and its grey cap.
        context.move(to: pivot)
        context.addLine(to: point(needle, radius * 0.96))
        context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setLineWidth(max(0.8, face.height / 45))
        context.strokePath()
        let cap = face.height * 0.22
        context.move(to: CGPoint(x: face.midX - cap * 0.7, y: face.maxY))
        context.addLine(to: CGPoint(x: face.midX, y: face.maxY - cap))
        context.addLine(to: CGPoint(x: face.midX + cap * 0.7, y: face.maxY))
        context.closePath()
        context.setFillColor(CGColor(gray: 0.72, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    /// The spectrum's bands as waves, as loud as the output, on the channel the trace names.
    func drawWaveForm(_ trace: AIMPControlClass.Trace, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let inner = rect.insetBy(dx: 2, dy: 2)
        let spectrum = host.feedback.spectrum
        guard inner.width > 2, !spectrum.isEmpty, host.player.playState == .playing else { return }
        let channel = trace.channel == "ssRight" ? host.feedback.levelR : trace.channel == "ssLeft" ? host.feedback.levelL
            : max(host.feedback.levelL, host.feedback.levelR)
        let bands = 12
        let amplitudes = (0..<bands).map { band -> Double in
            let from = band * spectrum.count / bands, to = max(from + 1, (band + 1) * spectrum.count / bands)
            return spectrum[from..<min(to, spectrum.count)].max() ?? 0
        }
        let total = max(0.001, amplitudes.reduce(0, +))
        let path = CGMutablePath()
        for step in 0...Int(inner.width) {
            let x = Double(step) / Double(inner.width)
            var y = 0.0
            for (band, amplitude) in amplitudes.enumerated() {
                let frequency = Double(band + 1) * 3
                y += amplitude * sin(2 * .pi * frequency * x + host.feedback.clock * Double(band + 2) * 2.3)
            }
            let point = CGPoint(x: inner.minX + CGFloat(step), y: inner.midY - CGFloat(y / total * min(1, channel * 1.4)) * inner.height / 2)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        context.saveGState()
        context.clip(to: inner)
        context.setStrokeColor(AIMPSkinText.color(trace.color ?? 0xFF80_E0FF))
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// `ColumnsCount` bars across the rect, `ColumnsIndent` apart, each as tall as its share of the
    /// spectrum, in the control's `Color` (a light default when it names none).
    func drawSpectrum(_ spectrum: AIMPControlClass.Spectrum, in rect: CGRect) {
        let levels = host.feedback.spectrum
        guard !levels.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let columns = spectrum.columns, indent = spectrum.indent
        let width = (rect.width - indent * CGFloat(columns - 1)) / CGFloat(columns)
        guard width > 0 else { return }
        context.setFillColor(AIMPSkinText.color(argb(spectrum.color) ?? 0xD0E0_E8F0))
        // A `PeakColumns` picture is the display fully lit (Sony TC-RX80's LED ladders): each column
        // reveals it up to its level, in whole `PeakColumnsSegmentation`-px segments.
        let lit = image(spectrum.peakColumns)?.frame(0)
        let segment = spectrum.peakSegment
        for i in 0..<columns {
            let from = i * levels.count / columns, to = max(from + 1, (i + 1) * levels.count / columns)
            let level = levels[from..<min(to, levels.count)].max() ?? 0
            var height = (rect.height * CGFloat(min(1, max(0, level)))).rounded()
            let column = CGRect(x: rect.minX + CGFloat(i) * (width + indent), y: rect.maxY - height, width: width, height: height)
            guard let lit else {
                context.fill(column)
                continue
            }
            height = (height / segment).rounded(.down) * segment
            context.saveGState()
            context.clip(to: CGRect(x: column.minX, y: rect.maxY - height, width: column.width, height: height))
            canvas.drawUpright(lit, in: rect)
            context.restoreGState()
        }
    }
}
