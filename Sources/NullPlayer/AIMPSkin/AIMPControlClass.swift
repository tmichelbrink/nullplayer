import CoreGraphics

/// An AIMP control's `class`, read once with what that class alone reads (`reference/layout.md` §
/// Controls). Classes are matched by name, some by prefix (`ScrollBar…`, `TextDisplay…`,
/// `Slider…`); a control bound to one of NullPlayer's lists is that list's whatever its class. One
/// the renderer has no drawing of its own for is a key: its picture's frame by state, a panel's
/// fill, a caption (`Key`).
enum AIMPControlClass: Sendable {
    case key(Key)
    /// `Slider`, `SliderHorizontal`, `SliderVertical`…, and `SeekBar`.
    case slider(Slider)
    /// `SliderMasked`: a filmstrip of positions (a knob's turn, a selector's positions).
    case selector
    /// `DigitsDisplay`, and `TimeDisplay`'s 13-frame strip.
    case digits(Digits)
    case time(Digits)
    /// `Gauge`: a filmstrip of needle positions, eased by the window where it gives reaction speeds.
    case gauge(reaction: (up: Double, down: Double)?)
    case animator(Animator)
    /// `StateDisplay`: the frame its `State` names (Teac V-8BL 4K's counter drums).
    case stateDisplay
    case spectrum(Spectrum)
    /// `VisualDisplay`: AIMP's visualization screen, where NullPlayer draws the spectrum under the
    /// picture's `CoverFrame` (RealPlayer 11's gloss).
    case visualization(Spectrum, cover: Int?)
    case waveForm(Trace)
    /// `EqualizerDisplay`'s `ColorPreamp` and `ColorCurve`, ARGB, when not clear.
    case equalizer(preamp: UInt32?, curve: UInt32?)
    case coverArt(Cover)
    /// `BlurredGlass`: what is drawn under it, blurred by `BlurLevel`, inside its mask frame, tinted
    /// by its `Color`.
    case glass(blur: Double?, tint: AIMPSkinColor?)
    /// `WaveformDisplay`: the playing track's waveform, played part lit, a seek bar (M5's wave and
    /// half-wave progress bars).
    case waveform(background: AIMPSkinColor?, content: AIMPSkinColor?)
    /// `Rating`: five stars of its picture; with no picture, a key's (`Key`).
    case rating(Key)
    /// `PageSelector`: a cell of its picture for each page of the tabbed group its `Action` names
    /// (`Pages`), the shown one lit; a click on a cell shows that page (M5's, Red Bias's, A4's and
    /// Soot's info-page dots).
    case pageSelector(group: String?)
    /// NullPlayer's lists placed in the skin's frame, in the skin's colours and fonts: the playlist
    /// (`<control link="Playlist">`), the library's group tree and table (`"MLGroupingTree"`, `"MLTable"`).
    case playlist(AIMPSkinControl.Playlist)
    case libraryTree(AIMPSkinControl.Library)
    case libraryTable(AIMPSkinControl.Library)
    /// A scroll bar bound to the playlist, and its `SkinThumb`.
    case playlistScrollBar(thumb: String?)
    /// A scroll bar bound to a scroll view's `ScrollBarVert` (M5's skin settings).
    case viewScrollBar(view: String, thumb: String?)
    /// A list's quick search box (a `SearchEdit` bound to a list's `QuickSearch`; `.acs3`'s
    /// `<control link="PlaylistSearch">`).
    case search(AIMPSkinList)
    /// AIMP 4's `TabControl` over a playlist or library manager (over anything else it is a key),
    /// and `PlaylistTabs`.
    case tabControl(AIMPSkinControl.Tabs, manager: String)
    case playlistTabs(AIMPSkinControl.Tabs)
    /// `PlaylistBox`, the playlist chooser: `.acs3`'s one-value `Font`, and `TextAlign` centred.
    case playlistBox(font: AIMPSkinFont?, centred: Bool)

    /// What a control the renderer draws as its picture is: a key with hot, pressed and disabled
    /// frames (`Button`; `Switch` with a run of them per state), a display of text, or any other.
    struct Key: Sendable {
        enum Role: Sendable, Equatable { case button, `switch`, textDisplay, runningLine, picture }
        let role: Role
        /// A `Panel`'s `Color`, which fills it under its picture (Unsquareable's light theme).
        let fill: AIMPSkinColor?
        /// `Frame`: a fixed picture (an AIMP 3.0 skin's lit playlist tab); `FramesPerState`, as declared.
        let fixedFrame: Int
        let framesPerState: Int?

        /// Keys have normal, hot, pressed and disabled frames.
        var isKey: Bool { role == .button || role == .switch }
        /// Draws its caption or bound text over its picture.
        var showsText: Bool { role == .button || role == .textDisplay || role == .runningLine }
    }

    struct Slider: Sendable {
        let isSeek: Bool
        /// Turned upright: `SliderVertical`, or `Orientation` oVertical (Kenwood KX-4520's EQ).
        let isVertical: Bool
        /// `SkinThumb`.
        let thumb: String?
        /// A seek bar's `ColorProgress` and `Color`, which it draws a track's waveform in (M5).
        let progressColor: AIMPSkinColor?
        let color: AIMPSkinColor?
    }

    /// `Digits` and `IndentBetweenDigits` of a digit strip.
    struct Digits: Sendable {
        let places: Int?
        let indent: Int
    }

    /// An animator's `AnimationInterval` and `AnimationReversed`, as written.
    struct Animator: Sendable {
        let interval: Double?
        let reversed: Bool
    }

    /// A spectrum's `ColumnsCount` and `ColumnsIndent`, its bars' `Color`, and the lit display it
    /// reveals (`PeakColumns`, in `PeakColumnsSegmentation`-px steps).
    struct Spectrum: Sendable {
        let columns: Int
        let indent: CGFloat
        let color: AIMPSkinColor?
        let peakColumns: String?
        let peakSegment: CGFloat
    }

    /// An oscilloscope's trace colour (`ColorContent`, a Delphi colour) and channel (`Source`).
    struct Trace: Sendable {
        let color: UInt32?
        let channel: String?
    }

    /// A cover display's `CoverFrame` laid over it (RealPlayer 11's gloss) and `BlurLevel` (Soot's
    /// backdrop); its mask is the control's `maskFrame` (SL-1200's round label).
    struct Cover: Sendable {
        let coverFrame: Int?
        let blur: Double?
    }

    /// A key, or a control drawn as one.
    var key: Key? {
        switch self {
        case .key(let key), .rating(let key): return key
        default: return nil
        }
    }
}
