import Foundation

extension AIMPSkinControl {
    /// What a key's caption or a display shows, and in what font, read once.
    struct Text: Sendable {
        /// Its `Font`, else its `Fonts`' `Normal`.
        let font: AIMPSkinFont
        let display: Display
        /// A `RunningLine` with nothing bound to it scrolls the playing track, by its `Template`;
        /// nil when a `DisplayValue` binding says what it shows.
        let running: String?
        /// `Alignment`, else `TextAlign`; whether `Alignment` (or a `TextAlign` not left) is there at
        /// all, and whether `Alignment` says `taLeftJustify`.
        let alignment: AIMPSkinTextAlign?
        let declaresAlignment: Bool
        let isLeftJustified: Bool
        /// `WordWrap`, or a `MultiLine` layout: it breaks into lines down from its top.
        let wraps: Bool
        /// `AutoSize` `csHeight`: as tall as its lines; and whether `AutoSize` is there at all.
        let sizesHeight: Bool
        let declaresAutoSize: Bool

        /// Where a display's text comes from.
        enum Display: Sendable {
            case none
            /// Its `Caption` (`@Lng:` strings filled in).
            case caption(String)
            /// Bound to nothing: its own `Template` (window titles, RealPlayer 11's skin-info lines).
            case template(String)
            /// A `FileInfo` binding: its `Template`, else the link's `TextFormat` (`%Title`).
            case file(String)
            /// A text provider (Sony Media Tower's file type, volume): its template over its inputs.
            case concatenation(inputs: [AIMPSkinLink], template: String)
            /// A number (the clock, the position): through a template, else as AIMP writes it.
            case number(AIMPSkinLink, template: String?)
        }

        init(_ node: AIMPNode, bindings: AIMPSkinBindings, index: AIMPSkinIndex) {
            let props = node.properties
            func expanded(_ text: String) -> String { AIMPSkinLanguage.expanded(text, strings: index.strings) }
            font = AIMPSkinFont(props["Font"] ?? props["Fonts"]?.named["Normal"], resources: index.resources)
            let template = props["Template"]?.reference
            if let caption = props["Caption"]?.reference {
                // A caption with a language string inside it (`Akai GX-635D - @Lng:10;`) has it filled in.
                display = .caption(expanded(caption))
            } else if let file = bindings.links.first(where: { $0.pin == "FileInfo" && $0.target == "DisplayValue" }) {
                // Language strings inside it too (Red Bias's `@Lng:15; %PlayCount`: "Played: 3").
                display = .file(expanded(template ?? file.textFormat ?? "%T"))
            } else if let link = bindings["DisplayValue"] {
                if let source = link.source, let provider = index.providers[source], provider.kind == .concatenator {
                    // No `Expression`: its first input's text.
                    display = .concatenation(inputs: provider.bindings.links,
                                             template: expanded(provider.node.properties["Expression"]?.reference ?? "%TextValue1"))
                } else {
                    // A template over the bound number (`%time(MS;:;)`).
                    display = .number(link, template: (template ?? link.textFormat).map(expanded))
                }
            } else {
                display = template.map { .template(expanded($0)) } ?? .none
            }
            running = bindings["DisplayValue"] == nil ? template.map(expanded) ?? "%IF(%R,%R - ,)%T" : nil
            alignment = AIMPSkinTextAlign(props["Alignment"]?.reference ?? props["TextAlign"]?.reference)
            // `.acs3`'s `TextAlign` other than left counts too: such a label is not the left-aligned
            // one AIMP sized to its text (`AIMPSkinLayout.autoSized`).
            declaresAlignment = props["Alignment"] != nil || AIMPSkinTextAlign(props["TextAlign"]?.reference).map { $0 != .left } == true
            isLeftJustified = AIMPSkinTextAlign(props["Alignment"]?.reference) == .left
            wraps = props["WordWrap"]?.reference == "True" || props["Layout"]?.reference == "MultiLine"
            sizesHeight = props["AutoSize"]?.reference == "csHeight"
            declaresAutoSize = props["AutoSize"] != nil
        }
    }

    /// The playlist's `Resources`, in `.acs3`'s flat form (`ItemLine1FontPlaying`) or `.acs4`/`.acs5`'s
    /// nested one (`ItemLine1Fonts/Playing`).
    struct Playlist: Sendable {
        enum Row: String, Sendable, CaseIterable {
            case normal = "Normal", playing = "Playing", selected = "Selected", playingSelected = "PlayingSelected"
        }

        /// Its own background picture (GX-77's paper sheet), else its background colour.
        let picture: String?
        /// Its colours as the skin gives them, a value or a colour resource the painter reads through
        /// the theme's aliases (Sony Media Tower Reborn's white list, `Skin.FFFFFFFF`).
        let background: AIMPSkinColor?
        /// `ItemBackground`: a picture under every row (Sony Media Tower Reborn's white rows, its
        /// list's own colour black).
        let rowPicture: String?
        /// Each row's font and its fill (the normal row has none of its own).
        let fonts: [Row: AIMPSkinFont]
        let fills: [Row: AIMPSkinColor]
        /// AIMP's second line, the track's format and size (`ItemLine2Fonts`), by row state.
        let detailFonts: [Row: AIMPSkinFont]
        /// A group's header (`HeaderFonts`), its picture under it (`HeaderBackground`) and its
        /// expand button (`HeaderExpandButtons`: collapsed, expanded).
        let headerFont: AIMPSkinFont
        let headerPicture: String?
        let expandButtons: String?
        /// A track's rating marks (`ItemMarks`, earlier `SkinMarks`: unrated, rated), the switch beside
        /// each row (`ItemSwitches`, earlier `SkinSwitches`) and beside each header (`HeaderSwitches`).
        let marks: String?
        let switches: String?
        let headerSwitches: String?
        /// AIMP 2's list: one line a track, no group headers (`AIMPSkinIndex.classicPlaylist`).
        let classic: Bool

        init(_ props: [String: AIMPNode], resources ids: [String: [String: AIMPNode]], delphiColors: Bool = true, classic: Bool = false) {
            self.classic = classic
            let resources = props["Resources"]?.named ?? [:]
            let color = { (flat: String, nested: String, state: String) in
                Self.color(resources, flat: flat, nested: nested, state: state, delphi: delphiColors)
            }
            picture = resources["Skin"]?.reference ?? resources["Background"]?.reference
            rowPicture = resources["ItemBackground"]?.reference
            background = color("BackgroundColor", "BackgroundColor", "")
            let normal = Self.font(resources, "Normal", ids: ids) ?? AIMPSkinFont(name: "Tahoma", height: 13, bold: false, color: 0xFFC0_C0C0)
            fonts = Dictionary(uniqueKeysWithValues: Row.allCases.map { ($0, Self.font(resources, $0.rawValue, ids: ids) ?? normal) })
            // With none of its own, the second line is the first's font, smaller.
            var small = normal
            small.height = max(9, normal.height - 2)
            let detail = Self.font(resources, "Normal", line: "ItemLine2", ids: ids) ?? small
            detailFonts = Dictionary(uniqueKeysWithValues: Row.allCases.map {
                ($0, Self.font(resources, $0.rawValue, line: "ItemLine2", ids: ids) ?? detail)
            })
            headerFont = Self.font(resources, "Normal", line: "Header", ids: ids) ?? normal
            headerPicture = resources["HeaderBackground"]?.reference
            expandButtons = resources["HeaderExpandButtons"]?.reference
            marks = (resources["ItemMarks"] ?? resources["SkinMarks"])?.reference
            switches = (resources["ItemSwitches"] ?? resources["SkinSwitches"])?.reference
            headerSwitches = resources["HeaderSwitches"]?.reference ?? switches
            var fills: [Row: AIMPSkinColor] = [:]
            fills[.playingSelected] = color("ItemHighlightColorSelectedPlaying", "ItemBackgroundColors", "PlayingSelected")
            fills[.playing] = color("ItemHighlightColorPlaying", "ItemBackgroundColors", "Playing")
            fills[.selected] = color("ItemHighlightColorSelected", "ItemBackgroundColors", "Selected")
            self.fills = fills
        }

        /// A row's font: `.acs3`'s flat `ItemLine1Font…`, else its state's (else the normal one's) in
        /// `ItemLine1Fonts`, in `.acs3`'s one value (W10, New.VK: `Segoe UI,6842472,13,0`) or declared,
        /// over the list's own default, Tahoma 13.
        /// The header's and second line's likewise (`line` `Header`, `ItemLine2`).
        private static func font(_ resources: [String: AIMPNode], _ state: String, line: String = "ItemLine1",
                                 ids: [String: [String: AIMPNode]]) -> AIMPSkinFont? {
            if let flat = AIMPSkinFont(flat: resources[line + "Font" + (state == "Normal" ? "" : state)]?.reference) { return flat }
            let states = (resources[line + "Fonts"]?.named ?? [:])
            guard let node = states[state] ?? states["Normal"] else { return nil }
            // A state's `ID` is followed, so a theme's fonts reach the rows (M5's dark text in its
            // light theme); one that gives a clear colour keeps white: read so, Sony Media Tower
            // Reborn's rows drew nothing.
            let white = AIMPSkinFont(name: "Tahoma", height: 13, bold: false, color: 0xFFFF_FFFF)
            var font = AIMPSkinFont(node, resources: ids, fallback: white)
            if font.color >> 24 == 0, font.colorID == nil { font.color = white.color }
            return font
        }

        /// `.acs3`'s flat Delphi colour (`delphi`), else `.acs4`'s and `.acs5`'s, flat or nested by
        /// state, ARGB: there a flat `0` is clear, the list over its parent's picture (Arc's light
        /// pane; W10's dark one under a clear white `16777215`), not black.
        private static func color(_ resources: [String: AIMPNode], flat: String, nested: String, state: String, delphi: Bool) -> AIMPSkinColor? {
            if let property = resources[flat] {
                if delphi, let value = AIMPSkinColor.delphi(property) { return .argb(value) }
                if !delphi, let color = AIMPSkinColor(property) { return color }
            }
            return AIMPSkinColor(resources[nested].flatMap { state.isEmpty ? $0 : $0.named[state] })
        }
    }

    /// The colours of the library's group tree and table (`Style` in `.acs4`, `StyleContent` in
    /// `.acs5`): the list's fill, the chosen row in `RowColorSelected` with `RowColorSelectedText`,
    /// text in `RowColorText` or `ColorText`. NullPlayer's library browser, hosted over the lists,
    /// wears them (`AIMPSkinLibraryHost`).
    struct Library: Equatable, Sendable {
        private(set) var fill: UInt32?
        private(set) var selected: UInt32?
        private(set) var selectedText: UInt32?
        private(set) var rowText: UInt32?
        /// The same four as the skin gives them, a value or a colour resource (M5's theme colours),
        /// for `resolved`.
        private var sources: Sources
        private struct Sources: Equatable, Sendable {
            let fill: AIMPSkinColor?, selected: AIMPSkinColor?, selectedText: AIMPSkinColor?, rowText: AIMPSkinColor?
        }

        /// The colours now, each read through `visible` (the theme's aliases; clear is none).
        func resolved(_ visible: (AIMPSkinColor?) -> UInt32?) -> Library {
            var library = self
            (library.fill, library.selected, library.selectedText, library.rowText) =
                (visible(sources.fill), visible(sources.selected), visible(sources.selectedText), visible(sources.rowText))
            return library
        }

        init(_ props: [String: AIMPNode]) {
            func style(_ name: String) -> AIMPNode? {
                for group in ["StyleContent", "Style"] {
                    if let node = props[group]?.named[name] { return node }
                }
                return nil
            }
            func source(_ name: String) -> AIMPSkinColor? { AIMPSkinColor(style(name)) }
            sources = Sources(fill: source("ColorContent") ?? source("BackgroundColor"), selected: source("RowColorSelected"),
                              selectedText: source("RowColorSelectedText"), rowText: source("RowColorText") ?? source("ColorText"))
            // Before any theme is read, a value the skin gives outright.
            self = resolved { color in
                guard case .argb(let argb)? = color, argb >> 24 != 0 else { return nil }
                return argb
            }
        }
    }

    /// NullPlayer's one playlist as the skin draws its tabs: AIMP 4's `TabControl` over
    /// `prvPlaylistManager` (or the library's), and `PlaylistTabs`.
    struct Tabs: Sendable {
        /// The manager a `TabControl` is bound to; one bound to neither is a picture.
        let source: String?
        /// `SkinTab` (or `TabSkin`), and `TabsOptions`' `Skin`.
        let picture: String?
        let optionsPicture: String?
        /// A `TabControl`'s caption font; `PlaylistTabs`' lit tab's, and while playing.
        let font: AIMPSkinFont
        let activeFont: AIMPSkinFont
        let playingFont: AIMPSkinFont
        /// `VerticalLayout`: a column of tabs.
        let isVertical: Bool
        /// `TextOffsetsActive` (l, t, r, b), and the caption centred unless `TextAlignment` says not.
        let offsets: AIMPSkinImage.Margins?
        let isCentred: Bool

        init(_ node: AIMPNode, bindings: AIMPSkinBindings, resources: [String: [String: AIMPNode]]) {
            let props = node.properties
            let options = props["TabsOptions"]?.named ?? [:]
            source = bindings.links.first { ["prvPlaylistManager", "prvMusicLibraryManager"].contains($0.source ?? "") }?.source
            picture = props["SkinTab"]?.reference ?? props["TabSkin"]?.reference
            optionsPicture = options["Skin"]?.reference
            font = AIMPSkinFont(options["FontActive"] ?? options["Font"] ?? props["FontActive"] ?? props["Font"] ?? props["Fonts"]?.named["Active"],
                                resources: resources)
            activeFont = AIMPSkinFont(options["FontActive"] ?? options["Font"], resources: resources)
            playingFont = AIMPSkinFont(options["FontPlayingActive"] ?? options["Font"], resources: resources)
            isVertical = props["VerticalLayout"]?.reference == "True"
            offsets = AIMPSkinImage.Margins(options["TextOffsetsActive"]?.reference)
            isCentred = options["TextAlignment"]?.reference.map { AIMPSkinTextAlign($0) == .center } ?? true
        }
    }
}

/// Where a line of text sits across its box: `Alignment` (`TextAlign` in `.acs3`) `taLeftJustify`,
/// `taCenter`, `taRightJustify`; nil for anything else, which reads from the left.
enum AIMPSkinTextAlign: Sendable {
    case left, center, right

    init?(_ value: String?) {
        switch value {
        case "taLeftJustify": self = .left
        case "taCenter": self = .center
        case "taRightJustify": self = .right
        default: return nil
        }
    }
}

extension AIMPSkinFont {
    /// `.acs3`'s one-value font, `name,colour,height,style`: a Delphi colour and a style set
    /// (bit 0 bold).
    init?(flat value: String?) {
        let parts = (value ?? "").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, let colour = Int64(parts[1]), let height = Int(parts[2]), height != .min, let style = Int(parts[3]) else { return nil }
        self.init(name: parts[0], height: abs(height), bold: style & 1 != 0, color: AIMPSkinColor.argb(delphi: colour))
        emHeight = height < 0
    }

    /// AIMP's default font, where a skin names none: Tahoma (macOS ships it), whose narrow letters
    /// the skins are measured against (RealPlayer 11's "M.Library" key).
    static let standard = AIMPSkinFont(name: "Tahoma", height: 11, bold: false, color: 0xFFFF_FFFF)

    /// A font property, read one way wherever a skin gives one: a `Schema.xml` font (`TASEFont`) by
    /// `ID`, `.acs3`'s one value (`Tahoma,13952279,12,2`), or declared inline (`Name`, `Height`,
    /// `Style`, `Color`), each over the last; what none says is `fallback`'s.
    init(_ property: AIMPNode?, resources: [String: [String: AIMPNode]], fallback: AIMPSkinFont = .standard) {
        var font = fallback
        // A `TASEFont` is a whole font: what it leaves out is AIMP's for a resource (12 px), and its
        // colour is ARGB, clear included (Lumin's tab caption font).
        if let id = property?.named["ID"]?["value"], let chain = AIMPSkin.resource(id, in: resources)?.chain, !chain.isEmpty {
            font = AIMPSkinFont(resource: chain)
            font.resource = Resource(id: id, name: font.name, height: font.height, bold: font.bold, color: font.color)
        }
        if let whole = AIMPSkinFont(flat: property?.reference) { font = whole }
        self = property.map { AIMPSkinFont(declared: $0, over: font, clearIsDelphi: true) } ?? font
        // A face named empty (`.acs3`'s `,0,12,0`) is AIMP's default.
        if name.isEmpty { name = Self.standard.name }
    }

    /// A font resource from its `chain` (`AIMPSkin.resource`): each `Resource` over the one it names,
    /// and what none says AIMP's for a resource.
    init(resource chain: [AIMPNode]) {
        self = chain.reduce(AIMPSkinFont(name: "", height: 12, bold: false, color: 0xFFFF_FFFF)) {
            AIMPSkinFont(declared: $1, over: $0, clearIsDelphi: false)
        }
        if name.isEmpty { name = Self.standard.name }
    }

    /// `Name`, `Height`, `Style` and `Color` where `node` declares them, over `base`; a colour is
    /// ARGB, or, `clearIsDelphi` (a form's own fonts), with no alpha a Delphi colour (`66051`: near
    /// black), opaque.
    private init(declared node: AIMPNode, over base: AIMPSkinFont, clearIsDelphi: Bool) {
        self = base
        let declared = node.named.mapValues { $0["value"] ?? "" }
        if let name = declared["Name"], !name.isEmpty { self.name = name }
        // `Int.min` has no magnitude `abs` can give.
        if let height = declared["Height"].flatMap(Int.init), height != .min {
            self.height = abs(height)
            emHeight = height < 0
        }
        if let style = declared["Style"] { bold = style.contains("fsBold") }
        if let id = node.named["ColorID"]?["value"], !id.isEmpty { colorID = id }
        if let number = declared["Color"].flatMap({ Int64($0) }) {
            let argb = UInt32(truncatingIfNeeded: number)
            color = clearIsDelphi && argb >> 24 == 0 ? AIMPSkinColor.argb(delphi: number) : argb
        }
    }
}
