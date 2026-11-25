/// An AIMP data provider's `class` (`Schema.xml`'s `<provider>`): read once into the skin index, so
/// the dataflow, scripts and painter ask one question rather than matching class names.
enum AIMPProviderClass: Equatable, Sendable {
    /// `LogicalOperatorCounter`; `ScriptableOperatorCounter` runs its script on each new position.
    case counter(scripted: Bool)
    /// `LogicalOperatorCommutator`: `Result` is its `Expression` over its inputs.
    case commutator
    /// `StringOperatorConcatenator`: text joined from its inputs. `…Notificator` shows AIMP's
    /// passing notices over the same text (Bliss Compact Dark's title line); NullPlayer posts none.
    case concatenator
    /// `LogicalOperatorTimer`: fires its `Action` links every `Interval` ms.
    case timer
    /// `ScriptableEventHandler`: a script run when something executes it.
    case eventHandler
    /// `ScriptableVisualizationHandler`: a script run every frame over the spectrum.
    case visualizationHandler
    case other(String)

    init(_ name: String?) {
        switch name {
        case "LogicalOperatorCounter": self = .counter(scripted: false)
        case "ScriptableOperatorCounter": self = .counter(scripted: true)
        // A delayer passes its input on `Interval` ms later: read at once, a commutator with no
        // `Expression` (M5's wave seek bars swap their time for their waveform while hovered).
        case "LogicalOperatorCommutator", "LogicalOperatorDelayer": self = .commutator
        case "StringOperatorConcatenator", "StringOperatorConcatenatorNotificator": self = .concatenator
        case "LogicalOperatorTimer": self = .timer
        case "ScriptableEventHandler": self = .eventHandler
        case "ScriptableVisualizationHandler": self = .visualizationHandler
        default: self = .other(name ?? "")
        }
    }

    var isCounter: Bool { if case .counter = self { true } else { false } }
}

/// What a slider, knob or value key moves: one of the player's values, or a value only the skin
/// keeps (an effect NullPlayer lacks, `prvReverb`; a skin counter a knob turns). Parsed once from
/// the control's binding.
enum AIMPSkinProvider: Hashable, Sendable, CustomStringConvertible {
    case volume, balance, position, preamp
    /// AIMP's speed and tempo, both NullPlayer's (tempo-preserving) speed.
    case speed
    /// AIMP's pitch: NullPlayer's pitch shift (the Reference Tuning offset), the speed left alone.
    case pitch
    /// A NullPlayer EQ band (`AIMPSkinHostState.eqBand`).
    case equalizerBand(Int)
    case named(String)

    /// AIMP's sound effects, which NullPlayer does not have. They read off unless a skin's script sets
    /// them, as AIMP shows them with its effects off (Hameleon's CHORUS, ECHO, FLANGER and REVERB at
    /// the left), and their knobs cannot be turned (`AIMPSkinLayout`).
    static let soundEffects: Set<String> = ["prvTrueBass", "prvReverb", "prvEcho", "prvChorus", "prvFlanger", "prvEnhancer"]

    /// One of `soundEffects`.
    var isSoundEffect: Bool {
        if case .named(let name) = self { return Self.soundEffects.contains(name) }
        return false
    }

    init(_ name: String) {
        switch name {
        case "prvVolume": self = .volume
        case "prvBalance": self = .balance
        case "prvPlayerState", "prvPlayerPosition", "prvPosition": self = .position
        case "prvSpeed", "prvTempo": self = .speed
        case "prvPitch": self = .pitch
        default: self = .named(name)
        }
    }

    /// One of the player's providers (`prvVolume`, `prvReverb`), not the skin's own: AIMP names
    /// every one of them `prv…`. Nil for anything else.
    init?(player name: String) {
        guard name.hasPrefix("prv") else { return nil }
        self.init(name)
    }

    var description: String {
        switch self {
        case .volume: return "prvVolume"
        case .balance: return "prvBalance"
        case .position: return "prvPlayerState"
        case .preamp: return "prvEqualizer:Preamp"
        case .speed: return "prvSpeed"
        case .pitch: return "prvPitch"
        case .equalizerBand(let band): return "prvEqualizer:\(band)"
        case .named(let name): return name
        }
    }

    /// AIMP's script units, in which a script sets and reads the player's values: the balance −1…1,
    /// the EQ and preamp in dB (±12), the speed and tempo as a multiplier; the rest 0–1 already.
    /// `AIMPSkinCommand.set` takes the value as 0–1, the host's one unit.
    func value(script: Double) -> Double {
        switch self {
        case .balance: return (script + 1) / 2
        case .preamp, .equalizerBand: return (script + 12) / 24
        case .speed: return script - 0.5
        // 0, AIMP's middle, is no shift (Kenwood KX-4520's effect reset sets Pitch 0).
        case .pitch: return script + 0.5
        case .volume, .position, .named: return script
        }
    }

    /// A value 0–1 in the script's units (`value(script:)` the other way).
    func script(value: Double) -> Double {
        switch self {
        case .balance: return value * 2 - 1
        case .preamp, .equalizerBand: return value * 24 - 12
        case .speed: return value + 0.5
        case .pitch: return value - 0.5
        case .volume, .position, .named: return value
        }
    }
}
