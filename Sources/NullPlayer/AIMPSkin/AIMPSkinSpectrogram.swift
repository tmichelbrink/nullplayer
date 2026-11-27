import CoreGraphics
import Foundation

/// The spectrum over the last seconds, for `SpectrogramDisplay` (Vilma's amplifier windows, Dark's
/// level panels, Pioneer RT-707's playlist): each frame's bands at the clock it was drawn at, kept
/// while a spectrogram could still show them.
struct AIMPSkinSpectrumHistory: Sendable {
    /// Long enough for a spectrogram 1,000 px wide at `pixelsPerSecond`.
    static let seconds = 30.0
    private(set) var clocks: [Double] = []
    private(set) var frames: [[Float]] = []

    /// Records `bands` at `clock`; a clock no later than the last (a second window drawing the same
    /// frame) records nothing.
    mutating func record(_ bands: [Double], at clock: Double) {
        if let last = clocks.last, clock <= last { return }
        clocks.append(clock)
        frames.append(bands.map(Float.init))
        let stale = clocks.prefix { $0 < clock - Self.seconds }.count
        if stale > 0 {
            clocks.removeFirst(stale)
            frames.removeFirst(stale)
        }
    }

    /// The bands drawn last at or before `clock`; nil before the first.
    func bands(at clock: Double) -> [Float]? {
        var low = 0, high = clocks.count
        while low < high {
            let mid = (low + high) / 2
            if clocks[mid] <= clock { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? frames[low - 1] : nil
    }
}

/// How AIMP 5.40 draws a `SpectrogramDisplay`, measured in AIMP under Wine with test tones, bursts
/// and stepped levels: time runs right to left at about 33.5 px a second, the newest at the right
/// edge (`FlipHorizontally`: the left); frequency runs up from the bottom (`FlipVertically`: down
/// from the top) on AIMP's scale, 100 Hz 1.8% of the way up, 1 kHz 17.4%, 10 kHz 75.5%, the top
/// near 22 kHz; each pixel is `ColorBackground` blended toward `ColorContent` by the band's level.
/// What the control's link reads makes no difference: bound to a level (Dark's `LevelL`) it shows
/// the same spectrogram.
enum AIMPSkinSpectrogram {
    static let pixelsPerSecond = 33.5

    /// AIMP's frequency, by height from the bottom (0…1): the measured points, log-interpolated.
    private static let scale: [(height: Double, hertz: Double)] = [
        (0, 20), (0.018, 100), (0.057, 300), (0.174, 1_000), (0.39, 3_000), (0.755, 10_000), (1, 22_050),
    ]

    static func hertz(atHeight height: Double) -> Double {
        let h = min(1, max(0, height))
        guard let upper = scale.firstIndex(where: { $0.height >= h }), upper > 0 else { return scale[0].hertz }
        let a = scale[upper - 1], b = scale[upper]
        let t = (h - a.height) / (b.height - a.height)
        return exp(log(a.hertz) + t * (log(b.hertz) - log(a.hertz)))
    }

    /// The fractional band of `bands` (log-spaced, 20 Hz–20 kHz, NullPlayer's spectrum) at `hertz`.
    static func band(atHertz hertz: Double, bands: Int) -> Double {
        guard bands > 1 else { return 0 }
        let position = log(max(20, min(20_000, hertz)) / 20) / log(1_000)
        return position * Double(bands - 1)
    }

    /// The spectrogram as an image `width`×`height`, its top row first: clear where `history` has
    /// nothing yet, `content` over clear by level elsewhere (the background is filled under it).
    static func image(_ history: AIMPSkinSpectrumHistory, clock: Double, width: Int, height: Int, content: UInt32,
                      flippedHorizontally: Bool, flippedVertically: Bool) -> CGImage? {
        guard width > 0, height > 0, width <= 4_096, height <= 4_096 else { return nil }
        // Each row's band, top row first.
        let bandCount = history.frames.last?.count ?? 0
        guard bandCount > 0 else { return nil }
        let rows: [Double] = (0..<height).map { row in
            let fromBottom = (Double(height - 1 - row) + 0.5) / Double(height)
            let up = flippedVertically ? 1 - fromBottom : fromBottom
            return band(atHertz: hertz(atHeight: up), bands: bandCount)
        }
        let alpha = Double(content >> 24) / 255
        let red = Double((content >> 16) & 0xFF), green = Double((content >> 8) & 0xFF), blue = Double(content & 0xFF)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for column in 0..<width {
            let fromNewest = flippedHorizontally ? column : width - 1 - column
            guard let bands = history.bands(at: clock - Double(fromNewest) / pixelsPerSecond), bands.count == bandCount else { continue }
            for row in 0..<height {
                let position = rows[row], low = Int(position), high = min(bandCount - 1, low + 1)
                let t = Float(position - Double(low))
                let level = Double(min(1, max(0, bands[low] * (1 - t) + bands[high] * t))) * alpha
                guard level > 0.004 else { continue }
                // Premultiplied RGBA.
                let at = (row * width + column) * 4
                pixels[at] = UInt8(red * level)
                pixels[at + 1] = UInt8(green * level)
                pixels[at + 2] = UInt8(blue * level)
                pixels[at + 3] = UInt8(255 * level)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
