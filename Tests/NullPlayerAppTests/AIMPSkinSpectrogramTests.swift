import XCTest
@testable import NullPlayer

/// `AIMPSkinSpectrogram` against AIMP 5.40, measured under Wine on a 551×384 spectrogram: tones at
/// 100 Hz, 1 kHz and 10 kHz 7, 67 and 290 px up from the bottom; 1-s bursts 33.5 px apart, the
/// newest at the right edge.
final class AIMPSkinSpectrogramTests: XCTestCase {
    /// The rows a tone lights in an image `height` tall (`bands` NullPlayer bands, only the tone's lit).
    private func litRows(hertz: Double, height: Int, flipped: Bool = false) -> [Int] {
        let bands = 75
        let band = Int(AIMPSkinSpectrogram.band(atHertz: hertz, bands: bands).rounded())
        var history = AIMPSkinSpectrumHistory()
        history.record((0..<bands).map { $0 == band ? 1 : 0 }, at: 1)
        guard let image = AIMPSkinSpectrogram.image(history, clock: 1, width: 1, height: height, content: 0xFFFF_8000,
                                                    flippedHorizontally: false, flippedVertically: flipped),
              let data = image.dataProvider?.data as Data? else { return [] }
        return (0..<height).filter { data[$0 * image.bytesPerRow + 3] > 128 }
    }

    func testTonesSitWhereAIMPDrawsThem() {
        for (hertz, fromBottom) in [(100.0, 7), (1_000, 67), (10_000, 290)] {
            let rows = litRows(hertz: hertz, height: 384)
            let centre = rows.isEmpty ? -1 : 383 - (rows.first! + rows.last!) / 2
            XCTAssertEqual(Double(centre), Double(fromBottom), accuracy: 8, "\(hertz) Hz")
        }
        XCTAssertEqual(litRows(hertz: 1_000, height: 384, flipped: true).map { 383 - $0 }.sorted(),
                       litRows(hertz: 1_000, height: 384).sorted().map { $0 }, "FlipVertically: low frequencies at the top")
    }

    func testTimeRunsLeftAt33AndAHalfPixelsASecond() {
        var history = AIMPSkinSpectrumHistory()
        // A burst at 10 s, silence around it.
        for step in 0..<400 {
            let clock = Double(step) / 30
            history.record(Array(repeating: abs(clock - 10) < 0.02 ? 1 : 0, count: 75), at: clock)
        }
        let width = 200
        guard let image = AIMPSkinSpectrogram.image(history, clock: 12, width: width, height: 4, content: 0xFFFF_FFFF,
                                                    flippedHorizontally: false, flippedVertically: false),
              let data = image.dataProvider?.data as Data? else { return XCTFail("no image") }
        let lit = (0..<width).filter { data[2 * image.bytesPerRow + $0 * 4 + 3] > 0 }
        // 2 s old: 67 px in from the right edge.
        XCTAssertFalse(lit.isEmpty)
        XCTAssertEqual(Double(width - 1 - (lit.first ?? 0)), 67, accuracy: 2)
    }

    func testTheHistoryKeepsThirtySeconds() {
        var history = AIMPSkinSpectrumHistory()
        for step in 0...40 { history.record([Double(step)], at: Double(step)) }
        XCTAssertEqual(history.clocks.first, 10)
        XCTAssertEqual(history.bands(at: 25.5), [25])
        XCTAssertNil(history.bands(at: 9))
        history.record([99], at: 40)
        XCTAssertEqual(history.clocks.count, 31, "a second window drawing the same frame records nothing")
    }
}
