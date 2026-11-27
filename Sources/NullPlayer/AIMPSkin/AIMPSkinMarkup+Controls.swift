import CoreGraphics
import Foundation

// The controls of a skin's XML forms, read into the model (`AIMPSkinControl` and what it holds).
// The model is built only here from markup: a reader of another format builds it with the types'
// own initialisers.

extension AIMPSkinControl {
    /// A control's XML node, kept for a script's restyle alone.
    struct Markup: Sendable {
        let node: AIMPNode
    }

    /// `controls`: the controls it holds, read (`AIMPSkinIndex` numbers them all).
    convenience init(_ node: AIMPNode, id: ID, index: AIMPSkinIndex, controls: [AIMPSkinControl]) {
        let props = node.properties
        let bindings = AIMPSkinBindings(node, names: index.names)
        let picture = props["Skin"]?.reference
        let handlers = Input.Handlers(props)
        self.init(id: id, name: node["name"], className: node["class"],
                  styleKey: node["name"].flatMap { $0.isEmpty ? nil : $0 } ?? node["link"],
                  kind: AIMPControlClass(node, bindings: bindings, resources: index.resources, dialect: index.dialect),
                  bindings: bindings, savedShown: AIMPSkinItem.Layout(node).savedShown,
                  placement: props["PlaceInfo"].map(AIMPPlacement.Info.init), controls: controls,
                  picture: picture,
                  maskFrame: (props["Skin"]?["MaskFrame"].flatMap { Int($0) }
                      ?? picture.flatMap { index.resources[$0]?.entry?.maskFrame }.flatMap { Int($0) })
                      .flatMap { $0 >= 0 ? $0 : nil },
                  opacity: Double(props["BlendingModeOpacity"]?.reference ?? "").flatMap { $0 < 255 ? $0 : nil },
                  blend: Self.blendMode(props["BlendingMode"]?.reference),
                  flipX: props["FlipHorizontally"]?.reference == "True", flipY: props["FlipVertically"]?.reference == "True",
                  text: Text(node, bindings: bindings, index: index),
                  input: Input(className: node["class"], handlers: handlers, bindings: bindings, index: index),
                  tag: props["Tag"]?["value"], writtenMargins: AIMPNode.writtenNumbers(props["PlaceInfo"]?["margins"]),
                  markup: Markup(node: node))
    }

    /// This control with properties a script set over its own (`AIMPNode.overriding`), read again;
    /// the controls it holds stay as they are. One with no markup is as it is.
    func restyled(_ sets: [String: String], index: AIMPSkinIndex) -> AIMPSkinControl {
        guard let markup else { return self }
        return AIMPSkinControl(markup.node.overriding(sets), id: id, index: index, controls: controls)
    }
}

extension AIMPSkinControl.Input.Handlers {
    /// A control's (or a menu item's) `OnClick`, mouse handlers, `PopupMenu` and `Hint`.
    init(_ props: [String: AIMPNode]) {
        self.init(onClick: props["OnClick"]?.reference, onMouseDown: props["OnMouseDown"]?.reference,
                  onMouseUp: props["OnMouseUp"]?.reference, onMouseEnter: props["OnMouseEnter"]?.reference,
                  onMouseMove: props["OnMouseMove"]?.reference, onMouseLeave: props["OnMouseLeave"]?.reference,
                  popupMenu: props["PopupMenu"]?.reference, hint: props["Hint"]?.reference)
    }
}

extension AIMPSkinControl.Text {
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
                                         template: expanded(provider.template ?? "%TextValue1"))
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

extension AIMPSkinControl.Playlist {
    init(_ props: [String: AIMPNode], resources ids: [String: AIMPSkinResource], dialect: AIMPSkinDialect) {
        let resources = props["Resources"]?.named ?? [:]
        let color = { (flat: String, nested: String, state: String) in
            Self.color(resources, flat: flat, nested: nested, state: state, delphi: dialect.delphiColors)
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
        classic = dialect.classicPlaylist
    }

    /// A row's font: `.acs3`'s flat `ItemLine1Font…`, else its state's (else the normal one's) in
    /// `ItemLine1Fonts`, in `.acs3`'s one value (W10, New.VK: `Segoe UI,6842472,13,0`) or declared,
    /// over the list's own default, Tahoma 13.
    /// The header's and second line's likewise (`line` `Header`, `ItemLine2`).
    private static func font(_ resources: [String: AIMPNode], _ state: String, line: String = "ItemLine1",
                             ids: [String: AIMPSkinResource]) -> AIMPSkinFont? {
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

extension AIMPSkinControl.Library {
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

extension AIMPSkinControl.Tabs {
    init(_ node: AIMPNode, bindings: AIMPSkinBindings, resources: [String: AIMPSkinResource]) {
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

extension AIMPControlClass {
    /// A control's class, by its `link` to one of NullPlayer's lists, else by its `class`, a scroll
    /// bar or search box bound to a list being that list's.
    init(_ node: AIMPNode, bindings: AIMPSkinBindings, resources: [String: AIMPSkinResource], dialect: AIMPSkinDialect) {
        let props = node.properties
        func number(_ name: String) -> Double? { Double(props[name]?.reference ?? "") }
        func integer(_ name: String) -> Int? { Int(props[name]?.reference ?? "") }
        let name = node["class"] ?? ""
        func keyed(_ role: Key.Role) -> Key {
            Key(role: role, fill: name == "Panel" ? AIMPSkinColor(props["Color"]) : nil,
                fixedFrame: integer("Frame") ?? 0, framesPerState: integer("FramesPerState"))
        }
        func key(_ role: Key.Role) -> AIMPControlClass { .key(keyed(role)) }
        func slider(seek: Bool) -> AIMPControlClass {
            .slider(Slider(isSeek: seek, isVertical: name == "SliderVertical" || props["Orientation"]?.reference == "oVertical",
                           thumb: props["SkinThumb"]?.reference,
                           progressColor: AIMPSkinColor(props["ColorProgress"]), color: AIMPSkinColor(props["Color"])))
        }
        // Held to ±4,096 px, as the spectrum's indent is: past a screen's width no gap means more, and
        // the painter's column arithmetic must stay inside `Int`.
        let digits = Digits(places: integer("Digits"), indent: min(max(integer("IndentBetweenDigits") ?? 0, -4_096), 4_096))
        // Past 4,096 columns no screen shows another bar, and each is drawn every frame.
        let spectrum = Spectrum(columns: min(max(1, integer("ColumnsCount") ?? 16), 4_096), indent: CGFloat(min(max(0, integer("ColumnsIndent") ?? 1), 4_096)),
                                color: AIMPSkinColor(props["Color"]), peakColumns: props["PeakColumns"]?.reference,
                                peakSegment: CGFloat(max(1, integer("PeakColumnsSegmentation") ?? 1)))
        // Read as `AIMPSkinControl.maskFrame` is: the `Skin`'s, else its resource's (Windows Media
        // Player 11's gloss, frame 2, over its cover).
        let coverFrame = (props["Skin"]?["CoverFrame"] ?? props["Skin"]?.reference.flatMap { resources[$0]?.entry?.coverFrame })
            .flatMap { Int($0) }
        switch node["link"] {
        case "PlaylistSearch"?: self = .search(.playlist); return
        case AIMPSkinList.playlist.rawValue?: self = .playlist(.init(props, resources: resources, dialect: dialect)); return
        case AIMPSkinList.libraryTree.rawValue?: self = .libraryTree(.init(props)); return
        case AIMPSkinList.libraryTable.rawValue?: self = .libraryTable(.init(props)); return
        default: break
        }
        switch name {
        case "Button": self = key(.button)
        case "Switch": self = key(.switch)
        case "SearchEdit":
            let list = bindings.links.first { $0.pin == "QuickSearch" }?.source.flatMap(AIMPSkinList.init(rawValue:))
            self = list.map { .search($0) } ?? key(.picture)
        case "TabControl":
            let tabs = AIMPSkinControl.Tabs(node, bindings: bindings, resources: resources)
            self = tabs.source.map { .tabControl(tabs, manager: $0) } ?? key(.picture)
        case "PlaylistTabs": self = .playlistTabs(AIMPSkinControl.Tabs(node, bindings: bindings, resources: resources))
        case "PlaylistBox":
            self = .playlistBox(font: AIMPSkinFont(flat: props["Font"]?.reference),
                                centred: AIMPSkinTextAlign(props["TextAlign"]?.reference) == .center)
        case "Gauge":
            let up = number("ReactionSpeedLevelUp") ?? 0, down = number("ReactionSpeedLevelDown") ?? 0
            self = .gauge(reaction: up > 0 && down > 0 ? (up, down) : nil)
        case "Animator": self = .animator(Animator(interval: number("AnimationInterval"), reversed: props["AnimationReversed"]?.reference == "True"))
        case "TimeDisplay": self = .time(digits)
        case "DigitsDisplay": self = .digits(digits)
        case "EqualizerDisplay": self = .equalizer(preamp: AIMPSkinColor.visible(props["ColorPreamp"]), curve: AIMPSkinColor.visible(props["ColorCurve"]))
        case "CoverArtDisplay":
            self = .coverArt(Cover(coverFrame: coverFrame, blur: number("BlurLevel")))
        case "WaveFormDisplay": self = .waveForm(Trace(color: AIMPSkinColor.delphi(props["ColorContent"]), channel: props["Source"]?.reference))
        case "Rating": self = .rating(keyed(.picture))
        case "PageSelector": self = .pageSelector(group: bindings.links.first { $0.target == "Action" && $0.pin == "Pages" }?.source)
        case "VisualDisplay": self = .visualization(spectrum, cover: coverFrame)
        case "SpectrumDisplay": self = .spectrum(spectrum)
        case "StateDisplay": self = .stateDisplay
        case "SliderMasked": self = .selector
        case "BlurredGlass": self = .glass(blur: number("BlurLevel"), tint: AIMPSkinColor(props["Color"]))
        case "WaveformDisplay": self = .waveform(background: AIMPSkinColor(props["ColorBackground"]), content: AIMPSkinColor(props["ColorContent"]))
        case "SeekBar": self = slider(seek: true)
        case "RunningLine": self = key(.runningLine)
        case let other where other.hasPrefix("ScrollBar"):
            if let view = bindings.links.first(where: { $0.pin == "ScrollBarVert" })?.source {
                self = .viewScrollBar(view: view, thumb: props["SkinThumb"]?.reference)
            } else {
                self = bindings.links.contains(where: { $0.source == AIMPSkinList.playlist.rawValue })
                    ? .playlistScrollBar(thumb: props["SkinThumb"]?.reference) : key(.picture)
            }
        case let other where other.hasPrefix("TextDisplay"): self = key(.textDisplay)
        case let other where other.hasPrefix("Slider"): self = slider(seek: false)
        default: self = key(.picture)
        }
    }
}

extension AIMPSkinFont {
    /// A font property, read one way wherever a skin gives one: a `Schema.xml` font (`TASEFont`) by
    /// `ID`, `.acs3`'s one value (`Tahoma,13952279,12,2`), or declared inline (`Name`, `Height`,
    /// `Style`, `Color`), each over the last; what none says is `fallback`'s.
    init(_ property: AIMPNode?, resources: [String: AIMPSkinResource], fallback: AIMPSkinFont = .standard) {
        var font = fallback
        // A `TASEFont` is a whole font: what it leaves out is AIMP's for a resource (12 px), and its
        // colour is ARGB, clear included (Lumin's tab caption font).
        if let id = property?.named["ID"]?["value"], let chain = AIMPSkin.resource(id, in: resources)?.chain, !chain.isEmpty {
            font = AIMPSkinFont(resource: chain)
            font.resource = Resource(id: id, name: font.name, height: font.height, bold: font.bold, color: font.color)
        }
        if let whole = AIMPSkinFont(flat: property?.reference) { font = whole }
        self = property.map { AIMPSkinFont(declared: Declaration($0), over: font, clearIsDelphi: true) } ?? font
        // A face named empty (`.acs3`'s `,0,12,0`) is AIMP's default.
        if name.isEmpty { name = Self.standard.name }
    }
}

extension AIMPPlacement.Info {
    init(_ property: AIMPNode) {
        anchors = AIMPNode.numbers(property["anchors"] ?? "1,1,0,0")
        margins = AIMPNode.numbers(property["margins"] ?? "0,0,0,0")
        let sizes = AIMPNode.numbers(property["Size"] ?? "0,0")
        size = sizes.count == 2 ? CGSize(width: sizes[0], height: sizes[1]) : nil
    }
}
