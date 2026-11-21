import Foundation

/// The state a skin keeps for itself, apart from the player's, in three parts by how often it moves:
/// what keys, scripts and bindings set (`script`), what moves every frame (`animation`), and where
/// the skin's own lists stand (`lists`). It starts empty: every group on its first page, every
/// counter at its default.
///
/// What is set on one of the skin's objects (a control, an item, a form or a provider: anything a
/// script's `FindObject` finds) is one typed record, by the object's name: `script[name]` is an
/// `Object`, `animation[name]` a `Motion`.
struct AIMPSkinState: Equatable, Sendable {
    var script = Script()
    var animation = Animation()
    var lists = Lists()

    /// Whether going from `old` to this can change which parts of a form show: anything but the
    /// animation (a page turned, an item shown, a list scrolled). The window measures its content
    /// again only then.
    func layoutMoved(from old: AIMPSkinState) -> Bool { script != old.script || lists != old.lists }

    /// What keys, bindings and scripts set: each object's `Object`, and what belongs to no one object.
    struct Script: Equatable, Sendable {
        var objects = Records<Object>()
        /// Resource aliases a script repointed (`Skin.BodyFace_` → `Skin.BodyFace_7`).
        var resourceLinks: [String: String] = [:]
        /// What the visualization screen shows (`acVisualNext` / `acVisualPrev` step it).
        var visualMode = AIMPVisualMode.spectrum
        /// What scripts stored with `ConfigSet`.
        var config: [String: String] = [:]
        /// The skin's variables a script has written (`AIMPSkinIndex.variables`), by lowercased name.
        var variables: [String: String] = [:]

        subscript(name: String) -> Object {
            get { objects[name] }
            set { objects[name] = newValue }
        }

        /// Items AIMP hid as the last layout found their parent smaller than their
        /// `AutoHideParentSizeThreshold` (or too small to hold them): bindings read them hidden
        /// (Soot's size triggers).
        var autoHidden: Set<String> {
            get { objects.names { $0.autoHidden } }
            set {
                for name in autoHidden.subtracting(newValue) { self[name].autoHidden = false }
                for name in newValue { self[name].autoHidden = true }
            }
        }

        /// Items and controls a script moved into another item (`Parent :=`), with the item each is in now.
        var parents: [String: String] { objects.values { $0.parent } }
    }

    /// What keys, bindings and scripts set on one object. Nil (empty) is what the skin wrote.
    struct Object: AIMPSkinStateRecord {
        /// The page a tabbed group shows (Vega MP-120's tape-type keys step it).
        var activePage: Int?
        /// A counter's position.
        var counter: Int?
        /// Shown or hidden (`FindObject(name).Set('Visible', …)`, a key bound to `Visible`).
        var visible: Bool?
        /// Hidden by `AutoHide` (`Script.autoHidden`).
        var autoHidden = false
        /// How far a scroll view is scrolled down, in skin pixels.
        var scrollTop: Double?
        /// Other properties a script set on a control or item, by dotted path (`Playlist.Set('Resources.BackgroundColor', …)`:
        /// Unsquareable's light theme), drawn over what the skin wrote (`AIMPNode.overriding`).
        var properties: [String: String] = [:]
        /// A text provider's `Expression` (Soot's `SetCustomLabels` labels its options so).
        var expression: String?
        /// A form docked or undocked (`AIMPSkinDockSites`).
        var docked: Bool?
        /// The item it was moved into (`Parent :=`).
        var parent: String?
        /// A timer switched on or off (`Set('Enabled', …)`) or retimed (`Set('Interval', …)`), and its
        /// `Accessibility` binding value as last seen, so a change hands the timer back to the binding.
        var timerEnabled: Bool?
        var timerInterval: Double?
        var timerGate: Double?
        /// Its `Visibility` bindings' value as last seen while a script had set it shown or hidden: a
        /// change hands it back to the bindings (`AIMPSkinScript.Engine.settle`).
        var visibleGate: Double?
        /// Margins it was moved to (`PlaceInfo.Margins.Left`…: 0 left, 1 top, 2 right, 3 bottom), and
        /// text a display was given (`Template`): the reel decks' position preview follows the pointer.
        var margins: [Int: Double] = [:]
        var text: String?
    }

    /// What moves every frame while the skin plays, each object's `Motion`. None of it moves a form's layout.
    struct Animation: Equatable, Sendable {
        var objects = Records<Motion>()

        subscript(name: String) -> Motion {
            get { objects[name] }
            set { objects[name] = newValue }
        }
    }

    /// Where one object's animation stands: a timer, an animator or lamp, the inputs a script last ran on.
    struct Motion: AIMPSkinStateRecord {
        /// When a `LogicalOperatorTimer` last fired, on the window's clock.
        var timerFired: Double?
        /// The inputs a script last ran on (`AIMPSkinScript.Engine.settle`, `AIMPSkinDataflow.inputs`).
        var scriptInputs: [Double]?
        /// An animator that keeps its own frame: one a script set (`Set('FrameIndex', 0)`: a speaker's
        /// visualization handler kicks its cone) or one that stops itself (`Accessibility` on its own
        /// `AnimationFrameIndex`), and when it last stepped; a `StateDisplay`'s `State` a script set.
        var frame: Int?
        var stepped: Double?
        /// Faded by a script (`Set('BlendingModeOpacity', 0–255)`: the color-music lamps).
        var opacity: Double?
    }

    /// One record per object name. An object with nothing set has none, so two states that set the
    /// same things are equal however they got there.
    struct Records<Record: AIMPSkinStateRecord>: Equatable, Sendable {
        private(set) var byName: [String: Record] = [:]

        subscript(name: String) -> Record {
            get { byName[name] ?? Record() }
            set { byName[name] = newValue == Record() ? nil : newValue }
        }

        /// The objects whose record says `test`.
        func names(_ test: (Record) -> Bool) -> Set<String> { Set(byName.filter { test($0.value) }.keys) }

        /// One part of each record, by name, where it is set.
        func values<Value>(_ part: (Record) -> Value?) -> [String: Value] { byName.compactMapValues(part) }
    }

    /// Where the skin's own playlist stands: scrolled, chosen, searched. Its library lists are
    /// NullPlayer's library browser, which keeps its own.
    struct Lists: Equatable, Sendable {
        /// The skin's own playlist: the track at the top of the view, the rows selected, and the row a
        /// Shift-click extends the selection from.
        var playlistTop = 0
        var playlistSelection: Set<Int> = []
        var playlistAnchor: Int?
        /// The skin playlist's quick search: only rows holding every word of it show.
        var playlistSearch = ""
        /// The list whose quick search the window is typing into (only "Playlist" takes one); its box
        /// then leaves the text to the field.
        var searchEditing: AIMPSkinList?

        /// The quick search of `list`; the library's lists keep none.
        func search(_ list: AIMPSkinList) -> String { list == .playlist ? playlistSearch : "" }

        /// A chosen row the search hides is no longer chosen.
        mutating func setSearch(_ list: AIMPSkinList, _ text: String) {
            guard list == .playlist else { return }
            playlistSearch = text
            playlistTop = 0
            select(nil)
        }

        /// A click on playlist row `row` (nil: none): it alone is selected; `extending` selects from
        /// the anchor to it; `toggling` adds or takes it out. As NullPlayer's other playlists select.
        mutating func select(_ row: Int?, extending: Bool = false, toggling: Bool = false) {
            guard let row else {
                playlistSelection = []
                playlistAnchor = nil
                return
            }
            if extending, let anchor = playlistAnchor {
                playlistSelection = Set(min(anchor, row)...max(anchor, row))
                return
            }
            if toggling {
                if playlistSelection.remove(row) == nil { playlistSelection.insert(row) }
            } else {
                playlistSelection = [row]
            }
            playlistAnchor = row
        }
    }
}

/// One object's record in `AIMPSkinState`: empty as made, and empty when nothing is set.
protocol AIMPSkinStateRecord: Equatable, Sendable {
    init()
}

/// What AIMP's visualization screen (`VisualDisplay`; AIMP 2's `MultiDisplay`) shows. AIMP steps
/// through its built-in visualizations with `acVisualNext` / `acVisualPrev` (AIMP 2's VisPrev and
/// VisNext keys), and shows the skin's own picture when none runs. NullPlayer offers its spectrum, a
/// scope, analog VU meters (PeppyMeter's) and none, in that order; the choice is kept per skin.
enum AIMPVisualMode: String, CaseIterable, Sendable {
    case spectrum, scope, vu, off

    /// The mode `steps` along the cycle, wrapping.
    func stepped(by steps: Int) -> AIMPVisualMode {
        let all = Self.allCases
        let at = all.firstIndex(of: self) ?? 0
        return all[((at + steps) % all.count + all.count) % all.count]
    }

    /// The mode last chosen for `skin`, kept by its name.
    static func saved(skin: String, defaults: UserDefaults = .standard) -> AIMPVisualMode? {
        defaults.string(forKey: key(skin)).flatMap(AIMPVisualMode.init(rawValue:))
    }

    func save(skin: String, defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key(skin))
    }

    private static func key(_ skin: String) -> String { "AIMPSkinVisual." + skin }
}
