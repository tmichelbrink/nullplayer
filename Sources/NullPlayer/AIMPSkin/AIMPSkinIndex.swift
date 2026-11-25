import Foundation

/// What a skin's forms and `Schema.xml` declare, looked up by name, and the forms themselves read
/// into typed items and controls (`AIMPSkinItem`, `AIMPSkinControl`): worked out once as the skin
/// loads (off the main thread) and never changed, so the dataflow, scripts and renderer read it
/// many times a frame without rescanning the trees or parsing properties again.
struct AIMPSkinIndex: Sendable {
    /// Each tabbed group's tabs, in order, and each tab's group and index.
    var groups: [String: [String]] = [:]
    var tabOf: [String: (group: String, index: Int)] = [:]
    /// The page each tabbed group starts on: its first not saved hidden, else its first. A group
    /// always shows one page; its pages' `Visible`/`InitialVisible` only say which (Unsquareable
    /// starts on its playlist view, its second page; RealPlayer 11's equalizer window holds one
    /// page saved hidden, and shows it when it opens).
    var initialPages: [String: Int] = [:]
    /// A tabbed group's `ActivePage` binding, by group (Soot's playlist and lyrics pages follow
    /// `LyricsVisibility`).
    var pageLinks: [String: AIMPSkinLink] = [:]
    /// Pages of two groups that show each other: each one's `Visibility` bound to the other's.
    /// AIMP pushes such a binding as the page changes, so turning one group turns the other; read as
    /// gates, the pair would only ever wait on each other (Bento's side panel `EkoGroup` and the
    /// playlist's `GroupL`, `Eko1`…`Eko7` with `ArtList`…`ArtList7`).
    var mirrors: [String: String] = [:]
    /// Each page's own `Visibility` bindings less its mirror's, by group, for the groups where any
    /// page has one (`AIMPSkinDataflow.shownPage`): read at load, not each frame.
    var pageGates: [String: [[AIMPSkinLink]]] = [:]
    /// The companions' names.
    var companions: Set<String> = []
    /// The forms the skin declares that NullPlayer does not open, and what they hold, by name.
    var elsewhere: Set<String> = []
    /// Items the form starts with hidden (`InitialVisible` False: Cassette-3D's VU meters), less
    /// tab pages and `AutoHide` items (`AIMPSkinAlignment.startsShown`).
    var hiddenItems: Set<String> = []
    /// `Schema.xml`'s providers, the skin's own dataflow, by name.
    var providers: [String: Provider] = [:]
    /// `Animator` controls in form order, and by name (one animator follows another's frame).
    var animatorList: [AIMPSkinControl] = []
    var animators: [String: AIMPSkinControl] = [:]
    /// `LogicalOperatorTimer` and `ScriptableVisualizationHandler` providers, by name order.
    var timers: [(name: String, provider: Provider)] = []
    var visualizationHandlers: [(name: String, provider: Provider)] = []
    /// Skin counters some control sets through an `Action` binding (selectors and keys).
    var selectorCounters: Set<String> = []
    /// Counters a key only fires (its `Action` or `ActionOnHold` bound to their `Position`, no
    /// `Expression`) and nothing reads: commands, run on the press alone (Sony Media Tower Reborn's
    /// `S0` and `S1` set its source to the player or the tape; `bREW` shows it rewinding).
    var commandCounters: Set<String> = []
    /// The menus the skin builds itself (`CustomContextMenu` providers), by name, read once the rest
    /// of the index is (`AIMPSkinCustomMenu`); their names are known before any key that opens one.
    var menuNames: Set<String> = []
    var customMenus: [String: AIMPSkinCustomMenu] = [:]
    /// What links are read against: the expressions, and the groups, items and providers the
    /// skin names. Read before anything else, so every link resolves as it is read (`AIMPSkinSource`).
    var names = Names()

    struct Names: Sendable {
        /// Every `Expression` the forms and `Schema.xml` hold (on links and as provider properties),
        /// compiled; one that does not parse is absent.
        var expressions: [String: AIMPSkinExpression] = [:]
        var groups: Set<String> = []
        /// Every form's items, and the companions: a companion's switches read and set the main
        /// form's, and the reverse.
        var items: Set<String> = []
        var providers: [String: AIMPProviderClass] = [:]
    }
    /// `Schema.xml`'s `<variables>`: names every script of the skin reads and writes (the GX-77
    /// 4K's reel diameters `D0`, `Dm`; Soot's `g_…` state and `gc_…` constants), by lowercased
    /// name, with the value they start at.
    var variables: [String: Variable] = [:]
    /// What the windows need of the forms before they draw, worked out here, off the main thread:
    /// each sizable form's sizing by name ("" the main form), the items and controls bindings read
    /// `IsActive` of (the window redraws as the pointer crosses them).
    var sizing: [String: Sizing] = [:]
    var hoverSources: Set<String> = []

    /// How the user sizes a form: how near its right and bottom edges a drag does
    /// (`SizingHitTestAreaWidth`), and the size it opens at before any is saved (`InitialSize`).
    struct Sizing: Sendable, Equatable {
        let edge: CGFloat
        let initialSize: CGSize?
    }

    /// `Schema.xml`'s resources by `ID`, and the `.lng` strings, which controls' fonts and texts
    /// are read through.
    var resources: [String: AIMPSkinResource] = [:]
    /// What the skin's file format decides (`AIMPSkinDialect`).
    var dialect = AIMPSkinDialect.modern
    var strings: [String: String] = [:]

    /// The main form's dock sites by name, and each docked form's site (`AIMPSkinDockSites`), and
    /// the item each site holds its form in while it is docked.
    var sites: [String: AIMPSkinDockSites.Site] = [:]
    var siteOf: [String: String] = [:]
    var holders: [String: AIMPSkinItem] = [:]
    /// Every named item and control, and the item it sits in: a script may move one into another
    /// (`FindObject('liMlTable').Parent := FindObject('liAioTableHost')`: Soot's all-in-one mode).
    var byName: [String: Element] = [:]
    var parentOf: [String: String] = [:]
    /// The main form (nil) and each companion's, read.
    private var forms: [String: AIMPSkinItem] = [:]
    /// Controls a script restyled, read again once per set of properties (`control(_:restyledBy:)`):
    /// a theme a script picked stays picked frame after frame (Unsquareable's light theme), and is
    /// read once, not every frame.
    private let restyled = AIMPSkinCache<Restyle, AIMPSkinControl>(limit: 1024)

    struct Variable: Sendable, Equatable {
        let value: String
        /// `String` (else a number; `Bool` reads `True` as 1).
        let isText: Bool
    }

    /// An item or a control, found by name.
    enum Element: Sendable {
        case item(AIMPSkinItem)
        case control(AIMPSkinControl)

        var name: String? {
            switch self {
            case .item(let item): return item.name
            case .control(let control): return control.name
            }
        }

        /// Its `class`, `Tag` and `PlaceInfo` margins as the skin wrote them, which a script reads.
        var className: String? {
            switch self {
            case .item(let item): return item.className
            case .control(let control): return control.className
            }
        }

        var tag: String? {
            switch self {
            case .item(let item): return item.tag
            case .control(let control): return control.tag
            }
        }

        var writtenMargins: [Double] {
            switch self {
            case .item(let item): return item.writtenMargins
            case .control(let control): return control.writtenMargins
            }
        }

        /// Its `Visibility` bindings.
        var gates: [AIMPSkinLink] {
            switch self {
            case .item(let item): return item.gates
            case .control(let control): return control.gates
            }
        }
    }

    /// A `Schema.xml` provider, read once: its class, bindings and the settings the dataflow and
    /// scripts read.
    struct Provider: Sendable {
        let kind: AIMPProviderClass
        let bindings: AIMPSkinBindings
        /// The script a scriptable one runs, by name.
        let script: String?
        /// A commutator's `Expression` over `value1…valueN`.
        let expression: String?
        /// A concatenator's `Expression`, its text's template, read as a reference (a resource's
        /// `link`, or the value) as other templates are.
        let template: String?
        /// A timer's `Interval`, ms.
        let interval: Double?
        /// A counter's `Module` (its positions) and `PositionDefault`.
        let module: Int?
        let positionDefault: Int
    }


    /// An index a reader builds itself: the names links resolve against, dock sites, sizing,
    /// resources and strings; the forms follow, read against it (`hold`).
    init(names: Names, companions: [AIMPSkin.Companion] = [], sites: [String: AIMPSkinDockSites.Site] = [:],
         sizing: [String: Sizing] = [:], resources: [String: AIMPSkinResource] = [:], strings: [String: String] = [:],
         dialect: AIMPSkinDialect = .modern) {
        self.names = names
        self.resources = resources
        self.dialect = dialect
        self.strings = strings
        self.sites = sites
        self.sizing = sizing
        siteOf = Dictionary(sites.map { ($0.value.form, $0.key) }, uniquingKeysWith: { first, _ in first })
        for companion in companions {
            self.names.items.insert(companion.name)
            self.companions.insert(companion.name)
            if !companion.initiallyVisible { hiddenItems.insert(companion.name) }
        }
    }

    /// The forms, read against this index: the main form, the companions' by name, and the item
    /// each dock site holds its form in while docked. Every item and control is then found by name,
    /// and the pages' gates are gathered.
    mutating func hold(main: AIMPSkinItem, companions: [(name: String, form: AIMPSkinItem)], holders: [String: AIMPSkinItem]) {
        forms[""] = main
        for (name, form) in companions where forms[name] == nil { forms[name] = form }
        self.holders = holders
        // In document order, as the skin wrote them: the first of a name is the one found.
        func walk(_ element: Element, in parent: String?) {
            let name = element.name.flatMap { $0.isEmpty ? nil : $0 }
            if let name, byName[name] == nil {
                byName[name] = element
                if let parent { parentOf[name] = parent }
            }
            if case .control(let control) = element, control.animator != nil { animatorList.append(control) }
            held(element, in: name ?? parent)
        }
        func held(_ element: Element, in holder: String?) {
            switch element {
            case .item(let item):
                let items = item.items.map(Element.item), controls = item.controls.map(Element.control)
                for each in item.itemsFirst ? items + controls : controls + items { walk(each, in: holder) }
            case .control(let control):
                for each in control.controls { walk(.control(each), in: holder) }
            }
        }
        for root in [forms[""]] + companions.map({ forms[$0.name] }) {
            if let root { held(.item(root), in: nil) }
        }
        animators = Dictionary(animatorList.compactMap { control in control.name.map { ($0, control) } },
                               uniquingKeysWith: { first, _ in first })
        for (group, pages) in groups {
            let gates = pages.map { page in
                (byName[page]?.gates ?? []).filter { !($0.source == mirrors[page] && $0.pin == "Visibility") }
            }
            if gates.contains(where: { !$0.isEmpty }) { pageGates[group] = gates }
        }
    }

    /// The form called `name`, read; the main form for nil.
    func form(_ name: String?) -> AIMPSkinItem? { forms[name ?? ""] }

    /// `text` compiled: the skin's own as it loaded, anything else (a wheel's step) now.
    func expression(_ text: String) -> AIMPSkinExpression? { names.expressions[text] ?? AIMPSkinExpression(text) }

    /// A counter provider's `Module` (its positions), nil for anything else.
    func counterModule(_ name: String) -> Int? {
        guard let provider = providers[name], provider.kind.isCounter else { return nil }
        return provider.module.flatMap { $0 > 1 ? $0 : nil }
    }

    /// A control as a script restyled it (`AIMPSkinState.Object.properties`), read again; as it loaded
    /// when none did.
    func control(_ control: AIMPSkinControl, restyledBy script: AIMPSkinState.Script) -> AIMPSkinControl {
        guard control.markup != nil, let key = control.styleKey, case let set = script[key].properties, !set.isEmpty else { return control }
        return restyled.value(Restyle(control: control.id, set: set)) { control.restyled(set, index: self) }
    }

    /// A control and the properties a script set on it.
    private struct Restyle: Hashable, Sendable {
        let control: AIMPSkinControl.ID
        let set: [String: String]
    }
}
