import Foundation
import NullPlayerCore

extension EQPreset {
    /// Sets `engine` to this preset: its preamp and its bands, read as the classic ten, each clamped
    /// to ±12 dB and remapped onto the engine's band layout. For a skin whose script or menu picks a
    /// preset by index (WMP's `eq.currentPreset`); turning the EQ on is the caller's.
    func apply(to engine: AudioEngine) {
        engine.setPreamp(Float(max(-12, min(12, preamp))))
        let clamped = bands.map { Float(max(-12, min(12, $0))) }
        let remapped = EQBandRemapper.remap(gains: clamped, from: .classic10, to: engine.eqConfiguration)
        for (band, gain) in remapped.enumerated() { engine.setEQBand(band, gain: gain) }
    }
}
