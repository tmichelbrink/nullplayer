import Foundation

/// What a skin asks of the player: from a key, a timer, a script or the skin's own lists, handed to
/// `AIMPSkinRuntime.onAction` and carried out by `AIMPSkinAudioEngineHost.perform`.
enum AIMPSkinCommand: Hashable, Sendable, CustomStringConvertible {
    /// One of AIMP's named actions (`acPlayerPlay`, `acMainShowPlaylist`…); one NullPlayer has no
    /// counterpart for is logged once and dropped.
    case action(AIMPAction)
    /// A script moved the player to a time in the track, in seconds as the skin writes it: Technics'
    /// counter reset rewinds to 0, the decks' REW/FF timers wind. A transport move, held short of the
    /// end as REW/FF is, not a value: a seek bar sets `.set(.position, …)`.
    case seek(seconds: Double)
    /// A slider, knob, key, wheel or script set one of the player's values, in the one unit every
    /// provider has: 0–1, as a control bound to it reads it back (`AIMPSkinPlayerSnapshot.value(for:)`).
    /// The host turns it into the engine's (dB, −1…1, a speed multiplier, a fraction of the track).
    /// A script's own units are turned into it where the script sets them (`AIMPSkinProvider.value(script:)`).
    /// An effect NullPlayer lacks (`prvReverb`…) is kept so its knob reads it back.
    case set(AIMPSkinProvider, Double)
    /// A row of the skin's own playlist, double-clicked or entered in its quick search.
    case playRow(Int)

    /// The form the action trace and the harness print.
    var description: String {
        switch self {
        case .action(let action): return action.name
        case .seek(let seconds): return "seek:\(seconds)"
        case .set(let provider, let value): return "set:\(provider):\(value)"
        case .playRow(let row): return "play:\(row)"
        }
    }
}
