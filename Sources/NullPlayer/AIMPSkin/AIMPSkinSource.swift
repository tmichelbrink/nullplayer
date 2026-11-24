import Foundation

/// What a binding reads: a link's `Source` and `SourcePin`, resolved once as the skin loads against
/// what the skin names (`AIMPSkinIndex.Names`), so a frame evaluates it with one exhaustive switch
/// (`AIMPSkinDataflow.value`) rather than matching strings. Scripts naming a source at run time
/// (`BindingsGetDataAsInteger`) resolve the same way. Anything not modelled, including a typo, is
/// `.value(0)`: what AIMP's own unknown pins read (`reference/layout.md` § *Visibility*).
indirect enum AIMPSkinSource: Sendable, Equatable {
    /// A tabbed group's page (`ActivePage`).
    case page(group: String)
    /// `IsActive`: whether the pointer is over a named item or control as last drawn; where the
    /// window has no pointer or has not drawn it (the probe), what the rest of the pin reads.
    case pointerOver(String, otherwise: AIMPSkinSource)
    /// `AnimationFrameIndex` of an animator that keeps its own frame; else what the rest reads.
    case animatorFrame(String, otherwise: AIMPSkinSource)
    /// An item's or form's visibility (any pin of it but `Maximize` and `Docked`).
    case item(String)
    /// A form's `Docked`: whether it is in its dock site (`AIMPSkinDataflow.isDocked`), not its
    /// visibility: AIMP Modern v3.63's library window hides its caption while docked.
    case docked(String)
    case value(Double)
    /// The player (`AIMPSkinHostState`).
    case player(PlayerPin)
    /// Whether the playlist runs past its window: its scroll bar shows only then (Onkyo TA-2250's
    /// `PlaylistScrollBarHost`).
    case playlistScrolls
    /// The library table's totals: NullPlayer's library browser shows its own, so these read
    /// nothing (`AIMPSkinDataflow`).
    case table(TablePin)
    case libraryScanning
    /// A text of NullPlayer's own, 0 as a number. Empty where it has none: the library's grouping
    /// preset (its browser shows its own), the playing track's live lyrics line (Soot shows it
    /// blurred over the cover while it is not empty; read as "0", that was always). Its one
    /// playlist's name, AIMP's first one's (WMP12 SB's label over its cover read "0").
    case text(String)
    /// The skin's own providers (`Schema.xml`): a commutator's `Result`, a concatenator's `Result`,
    /// a counter's `Position`.
    case commutator(String)
    case concatenator(String)
    case counter(String)

    enum TablePin: Sendable { case count, duration, size }

    /// A player pin, as `AIMPSkinHostState.value(_:)` reads it.
    enum PlayerPin: Sendable, Equatable {
        /// `prvVolume`'s `Position` as 0–1 (scripts set it so: Sony TC-MR2), its other pins 0–100.
        case volumeFraction, volume, balance, playState, timeOfDay, duration, elapsed, progress, hasCoverArt
        case playlistCount, playlistDuration, playlistSize
        case bitrate, sampleRate, channels, rating, ratingAvailable
        /// A clock's colon blinks each second (Revox B-710).
        case clockFlash
        case tracksStarted, tracksFinished, remaining
        /// The sleep timer's time left (`prvSleepTime`, `prvScheduler`): NullPlayer has none, so 0:00.
        case sleepTimer
        case levelL, levelR
        case nightMode, shuffle, repeatAll, stayOnTop, muted, equalizerOn
        /// `acPlayerPlayPause`'s `State`: on while playing (M5's simplified keys show pause then).
        case playing
        /// An action's `Action` read as a value: whether it can be taken now. 1, but for radio
        /// capture, which NullPlayer never offers (M5 shows its seek bar while `acPlayerStopAtEnd`
        /// can be, and its radio row only while `acPlayerRadioCapture` can). A player pin, not a
        /// constant: scripts read it through the host too (`AIMPSkinHostState.pin`).
        case actionAvailable(Bool)
        /// Whether the playing track's waveform is worked out (M5 swaps its plain seek bar for the wave one).
        case waveformEnabled
        /// NullPlayer's window for a form the skin does not draw (`AIMPFormRole.isOpen`).
        case window(AIMPFormRole)

        /// The pin `source`.`pin` of the player, nil for anything else. AIMP reads a pin's name
        /// without regard to case (`prvPlayerState.trackposition` is the position, not 0), so the
        /// pins below are matched in lower case.
        init?(_ source: String, _ pin: String) {
            switch (source, pin.lowercased()) {
            // Scripts ask an action whether it is on as `Checked`: Denon Classic Style's speakers
            // script mutes when its speakers go off unless already muted, and read as never muted it
            // took every mute straight back.
            case (_, "checked"): self.init(source, "state")
            // AIMP reads pin names without regard to case, and the two volume pins differ in unit.
            case ("prvVolume", "position"): self = .volumeFraction
            case ("prvVolume", _): self = .volume
            case ("prvBalance", _): self = .balance
            case ("prvPlayerState", "state"): self = .playState
            case ("prvSystemTime", "time"): self = .timeOfDay
            case ("prvPlayerState", "trackduration"), ("prvPlayerState", "positionmax"), ("prvPlayingFileInfo", "duration"): self = .duration
            case ("prvPlayerState", "trackposition"), ("prvPlayerState", "position"): self = .elapsed
            case ("prvPlayerState", "progress"): self = .progress
            case ("prvPlayingFileInfo", "coverart"): self = .hasCoverArt
            case ("Playlist", "count"): self = .playlistCount
            case ("Playlist", "duration"): self = .playlistDuration
            case ("Playlist", "size"): self = .playlistSize
            // AIMP reads pin names without regard to case; skins spell this one both ways.
            case ("prvPlayingFileInfo", "bitrate"): self = .bitrate
            case ("prvPlayingFileInfo", "samplerate"): self = .sampleRate
            case ("prvPlayingFileInfo", "channels"): self = .channels
            case ("prvPlayingFileInfo", "mark"): self = .rating
            case ("prvPlayingFileInfo", "markavailable"): self = .ratingAvailable
            case ("prvSystemTime", "flashing"): self = .clockFlash
            case ("prvSleepTime", "time"), ("prvScheduler", "time"): self = .sleepTimer
            case ("prvPlayerState", "ontrackstarted"): self = .tracksStarted
            case ("prvPlayerState", "ontrackfinished"): self = .tracksFinished
            case ("prvPlayerState", "trackpositionremaining"): self = .remaining
            case ("prvVisual", "levell"): self = .levelL
            case ("prvVisual", "levelr"): self = .levelR
            case ("prvPlayerPosition", _): self = .elapsed
            case ("AIMPMainForm", "nightmode"): self = .nightMode
            case ("acPlayerShuffle", "state"), ("acPlayerShuffleMode", "state"): self = .shuffle
            case ("acPlayerRepeat", "state"), ("acPlayerRepeatPlaylist", "state"): self = .repeatAll
            case ("acMainStayOnTop", "state"): self = .stayOnTop
            case ("acPlayerPlayPause", "state"): self = .playing
            case ("prvPlayingFileInfo", "waveformenabled"): self = .waveformEnabled
            case (let action, "action") where action.hasPrefix("ac"):
                self = .actionAvailable(AIMPAction(action) != .playerRadioCapture)
            case ("acPlayerVolumeMute", "state"): self = .muted
            case ("acEqualizerSwitch", "state"): self = .equalizerOn
            // NullPlayer's windows, under whatever prefix the skin gives them (`TA2066_PlaylistWindow`).
            case (let frame, "visible") where AIMPFormRole(frame).hasWindow: self = .window(AIMPFormRole(frame))
            default: return nil
            }
        }
    }

    /// `source`.`pin`, as the skin's `names` make it.
    init(_ source: String, _ pin: String, names: AIMPSkinIndex.Names) {
        if names.groups.contains(source), pin == "ActivePage" {
            self = .page(group: source)
            return
        }
        let rest = Self.rest(source, pin, names: names)
        switch pin {
        case "IsActive": self = .pointerOver(source, otherwise: rest)
        case "AnimationFrameIndex": self = .animatorFrame(source, otherwise: rest)
        default: self = rest
        }
    }

    private static func rest(_ source: String, _ pin: String, names: AIMPSkinIndex.Names) -> AIMPSkinSource {
        // A form's window is not maximized (Sony Media Tower Reborn's restore glyph showed). A list's
        // totals are the list's, though the skin names an item after it (Dark Blocks' `Playlist`), as
        // is whether its rows scroll.
        let listTotal = AIMPSkinList(rawValue: source) != nil && ["Count", "Duration", "Size", "Scrolling"].contains(pin)
        if names.items.contains(source), !listTotal {
            switch pin {
            case "Maximize": return .value(0)
            case "Docked": return .docked(source)
            default: return .item(source)
            }
        }
        switch (source, pin) {
        case ("Main", "IsActive"), ("AIMPMainForm", "Visible"), ("AIMPMainForm", "IsActive"): return .value(1)
        case ("AIMPMainForm", "StayOnTop"): return .player(.stayOnTop)
        // AIMP 5: skins hide their speakers and warn below 4.6 (`< 4600`, or `< 460`).
        case ("acMainAbout", "Version"): return .value(5_000)
        case ("Playlist", "Scrolling"): return .playlistScrolls
        case ("MLTable", "Count"): return .table(.count)
        case ("MLTable", "Duration"): return .table(.duration)
        case ("MLTable", "Size"): return .table(.size)
        case ("prvMusicLibraryManager", "BackgroundTaskCount"): return .libraryScanning
        case ("prvMusicLibraryManager", "GroupingPresets"), ("prvPlayingFileInfo", "LiveLyricsCurrentLine"): return .text("")
        case ("prvPlaylistManager", "ActivePlaylistName"): return .text(AIMPSkinList.playlistName)
        default: break
        }
        if let player = PlayerPin(source, pin) { return .player(player) }
        switch (names.providers[source], pin) {
        case (.commutator?, "Result"): return .commutator(source)
        case (.concatenator?, "Result"): return .concatenator(source)
        case (.counter?, "Position"): return .counter(source)
        default: return .value(0)
        }
    }
}
