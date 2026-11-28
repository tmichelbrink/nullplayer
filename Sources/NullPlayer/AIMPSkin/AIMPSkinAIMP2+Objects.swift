import CoreGraphics
import Foundation

extension AIMPSkinAIMP2 {
    /// AIMP 2's built-in objects that AIMP 3.0 writes as `[CustomObjects]`, by lowercased name.
    private static let builtIns = [
        "time": "ClassNumLabel;4", "brinfo": "ClassNumLabel;5", "srinfo": "ClassNumLabel;6",
        "playermode": "ClassStatusLabel;2", "spectrum": "ClassSpectrum", "seekbar": "ClassSeekBar",
        "ititle": "ClassTextLabel;1", "iartist": "ClassTextLabel;2", "ialbum": "ClassTextLabel;3", "igenre": "ClassTextLabel;5",
    ]
    /// The equalizer panel's own names for sliders the player has too.
    private static let aliases = [("balance", "BalanceSlider"), ("speed", "SpeedSlider")]
    /// The sleep timer's display: NullPlayer has no sleep timer.
    private static let withoutCounterpart: Set<String> = ["sleeptime"]
    /// What a `ClassTextLabel;N` shows: title, artist, album, year, genre.
    private static let labelTemplates = ["1": "%T", "2": "%R", "3": "%A", "4": "%Y", "5": "%G"]
    /// Version 2's objects with no parent that are not the equalizer's: the playlist's own
    /// parts (its title bar's keys, scroll bar and tab scroll keys) and quick file info.
    private static let playlistParts: Set<String> = ["plsmenu", "plsclose", "playlistscroll", "tcn", "tcp"]
    /// A digit strip's glyphs: 0–9, the separator, the minus and a blank, as AIMP 3's.
    private static let digitGlyphs = 13
    /// The largest window side a skin's `FormMinW`/`FormMinH` is taken at.
    private static let largestSide = 16_384

    /// One object as AIMP 2 places it, whichever version wrote it, before it is an `Object`.
    struct Placed {
        let name: String
        /// The panel's item.
        let item: String
        /// Left, top, right, bottom in the panel.
        let bounds: [Int]
        /// 0 keeps the left edge, 1 the right, 2 both, 3 neither.
        let align: Int
        /// The panel's size when the skin was saved (version 3's `ParentBounds`): a right-kept edge
        /// is measured from it, and what lies outside it does not show.
        let parentSize: CGSize?
        /// Its own keys (Font, TextAlign, Digits, Reverse, Static, Orientation, SkinFrames, Color,
        /// Peaks…), by lowercased key.
        var settings: [String: String]
        /// What it is when AIMP 3.0 would write it in `[CustomObjects]` (`ClassNumLabel;4`).
        var custom: String?
        /// The AIMP object it is or copies, lowercased.
        var base: String

        func setting(_ key: String) -> String? { settings[key.lowercased()] }
    }

    /// What `main.ini` says of the windows rather than their objects.
    struct Settings {
        /// The window sizes from its edges (`FormDisableResizing` 0).
        var sizingEdge: String?
        /// `[Playlist]`'s fonts (`Nrm`, `Act`, `Sel`, `SelAct`) and colours (`BK`, `ABK`, `SBK`, `SABK`).
        var playlist: [String: String] = [:]
        /// The lit tab's font.
        var activeTab: String?
        /// The window's least size (`FormMinW`/`FormMinH`).
        var minimumSize: CGSize?
    }

    // MARK: Pictures

    /// Each object's picture cut into its states, a slider's lit track as its second frame, the
    /// panels' stretching columns, the docked `BottomDock` state, the playlist tab.
    func layOut(_ images: inout [String: AIMPSkinImage], objects: [Placed], playlistDocked: Bool) {
        for object in objects {
            let key = object.name.lowercased()
            guard let image = images[key + ".img"] else { continue }
            let width = object.bounds[2] - object.bounds[0]
            var frames = Int(object.setting("SkinFrames") ?? "") ?? 0
            // A digit strip's glyphs may leave a column over (Digital Light's 144-px strip).
            if object.custom?.hasPrefix("ClassNumLabel") == true {
                frames = Self.digitGlyphs
            } else if frames <= 0 || image.width % frames != 0 {
                frames = width > 0 && image.width % width == 0 ? image.width / width : 1
            }
            images[key + ".img"] = image.laidOut(AIMPSkinImage.Layout(frames: frames))
            if let lit = images[key + "_sel.img"], frames == 1, let track = AIMPSkinImage.stacking([image, lit]) {
                images[key + ".img"] = track
            }
        }
        for (panel, columns) in stretchColumns() {
            if let image = images[panel + ".img"] { images[panel + ".img"] = image.laidOut(AIMPSkinImage.Layout(columns: columns)) }
        }
        if let dock = images["bottomdock.img"], dock.height > 1 {
            let state = dock.stackedFrame(playlistDocked ? 1 : 0, of: 2) ?? dock
            // The player is as wide as `MainClient`, and the dock under it is cut to that width
            // (Hameleon's is 348 px under a 338-px player: AIMP's window is 624 px, not 634).
            images["bottomdock.img"] = images["mainclient.img"].map { state.clipped(toWidth: $0.width) } ?? state
        }
        if let tab = images["activetab.img"] { images["tabctrltab.img"] = tab }
    }

    /// The two stretching columns of each panel, by lowercased panel name, from `TLC` and `TRC`
    /// (`x1,0,x2,0`); a panel with one stretches it as two halves.
    private func stretchColumns() -> [String: AIMPSkinImage.StretchColumns] {
        var ranges: [String: [[Int]]] = [:]
        if isVersion2 {
            for (key, value) in ini["SKIN_RECTS"]?.lines ?? [] where key.uppercased().hasSuffix("_TLC") || key.uppercased().hasSuffix("_TRC") {
                ranges[key.dropLast(4).lowercased(), default: []].append(AIMPNode.numbers(value))
            }
        } else {
            for section in ini.sections {
                // In any case, the first of each, as `TMemIniFile` reads a key (`tlc`, `TLC`).
                let corner = ["TLC", "TRC"].compactMap { section[$0] }.map { AIMPNode.numbers($0) }
                if !corner.isEmpty { ranges[section.name.lowercased()] = corner }
            }
        }
        return ranges.compactMapValues { corners in
            let spans = corners.filter { $0.count == 4 && $0[2] > $0[0] }.map { (x: $0[0], width: $0[2] - $0[0]) }.sorted { $0.x < $1.x }
            switch spans.count {
            case 2: return AIMPSkinImage.StretchColumns(spans[0], spans[1])
            case 1 where spans[0].width >= 2:
                let half = spans[0].width / 2
                return AIMPSkinImage.StretchColumns((spans[0].x, half), (spans[0].x + half, spans[0].width - half))
            default: return nil
            }
        }
    }

    // MARK: Objects

    /// The panel an object's parent names, as the item it is placed in; nil for AIMP's own windows.
    private static func item(ofPanel panel: String) -> String? {
        switch panel.lowercased() {
        case "main": return "MainFrame"
        case "eq": return "MainEquaFrame"
        case "top": return "TopPanel"
        case "btm": return "BottomPanel"
        case let container where container.hasPrefix("container"): return panel
        default: return nil
        }
    }

    /// Version 3: a section per object, in file order, its panel in `[Parents]`.
    func version3Objects() -> [Placed] {
        ini.sections.compactMap { section -> Placed? in
            guard let bounds = section["Bounds"].map(AIMPNode.numbers), bounds.count == 4,
                  let item = ini["Parents", section.name].flatMap(Self.item(ofPanel:)) else { return nil }
            let parent = section["ParentBounds"].map(AIMPNode.numbers)
            var settings: [String: String] = [:]
            for (key, value) in section.lines where settings[key.lowercased()] == nil { settings[key.lowercased()] = value }
            return Placed(name: section.name, item: item, bounds: bounds, align: Int(section["Align"] ?? "") ?? 0,
                          parentSize: parent.flatMap { $0.count == 4 ? CGSize(width: $0[2] - $0[0], height: $0[3] - $0[1]) : nil },
                          settings: settings, base: section.name.lowercased())
        }
    }

    /// Version 2: bounds in `[SKIN_OBJS]`, the rest in sections of their own.
    func version2Objects() -> [Placed] {
        let tray = Set((ini["TC_PARENTS"]?.lines ?? []).map { $0.key.lowercased() })
        return (ini["SKIN_OBJS"]?.lines ?? []).compactMap { name, value in
            let key = name.lowercased()
            let bounds = AIMPNode.numbers(value)
            guard bounds.count == 4, !tray.contains(key), !Self.playlistParts.contains(key), !key.hasPrefix("qfi"),
                  let item = Self.item(ofPanel: ini["PARENTS", key] ?? "EQ") else { return nil }
            var settings: [String: String] = [:]
            settings["font"] = ini["SKIN_FONTS", key]
            settings["textalign"] = ini["SKIN_TEXTALIGNS", key]
            settings["digits"] = ini["SKIN_WIDTHS", key + "digits"]
            settings["orientation"] = ini["SKIN_WIDTHS", key + "_horizontal"]
            switch key {
            case "aimpeqdisplay":
                settings["eqvise"] = ini["SKIN_FONTS", "EQVISE"]
                settings["eqvisl"] = ini["SKIN_FONTS", "EQVISL"]
            case "spectrum":
                settings["color"] = ini["SKIN_OPTIONS", "spectrumcolor"]
                settings["peaks"] = ini["SKIN_OPTIONS", "spectrumpeaks"]
            default: break
            }
            return Placed(name: name, item: item, bounds: bounds, align: Int(ini["SKIN_WIDTHS", key + "_align"] ?? "") ?? 0,
                          parentSize: nil, settings: settings, base: key)
        }
    }

    /// `[Clones]` (version 2: `[SKIN_VIRTUAL_OBJS]`), then the equalizer panel's aliases, by the copy's
    /// lowercased name, the first winning.
    private var clones: [String: String] {
        let own = (isVersion2 ? ini["SKIN_VIRTUAL_OBJS"] : ini["Clones"])?.lines ?? []
        return Dictionary((own + Self.aliases.map { (key: $0.0, value: $0.1) }).map { ($0.key.lowercased(), $0.value) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Each object's `[CustomObjects]` class: the skin's own (version 3), else the one AIMP 3.0
    /// gives AIMP 2's built-in object it is or clones; a text label's template; a digit strip's
    /// places, as many glyphs as fit when the skin gives none; a slider's direction, from its
    /// shape when the skin gives none.
    func classified(_ objects: [Placed]) -> [Placed] {
        let clones = self.clones
        return objects.filter { object in
            // A panel is a window: what lies outside it does not show (cPro Insomnis' labels in
            // its collapsed top panel).
            let b = object.bounds
            return !Self.withoutCounterpart.contains(object.name.lowercased())
                && CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]).intersects(CGRect(origin: .zero, size: panelSize(object)))
        }.map { object in
            var object = object
            object.base = AIMPSkinAIMP3.original(of: object.name, clones: clones)
            object.custom = ini["CustomObjects", object.name] ?? Self.builtIns[object.base]
            let width = object.bounds[2] - object.bounds[0], height = object.bounds[3] - object.bounds[1]
            let parts = object.custom?.split(separator: ";").map(String.init) ?? []
            if parts.first == "ClassTextLabel", object.setting("Template") == nil {
                object.settings["template"] = Self.labelTemplates[parts.count > 1 ? parts[1] : ""]
            }
            if parts.first == "ClassNumLabel", object.setting("Digits") == nil,
               let strip = images[object.name.lowercased() + ".img"], strip.width >= Self.digitGlyphs {
                object.settings["digits"] = String(width / (strip.width / Self.digitGlyphs))
            }
            if object.setting("Orientation") == nil, images[object.name.lowercased() + "_thumb.img"] != nil {
                object.settings["orientation"] = width > height ? "1" : "0"
            }
            return object
        }
    }

    /// The objects as AIMP 3.0 places them, stacked in the order found: `PlaceAnchors` and
    /// `PlaceMargins` from the bounds and `Align`.
    func objects(_ placed: [Placed]) -> [Object] {
        placed.enumerated().compactMap { z, object in
            guard let kind = AIMPSkinAIMP3.Kind(custom: object.custom, base: object.base, setting: object.setting) else { return nil }
            let b = object.bounds
            let right = Int(panelSize(object).width) - b[2]
            let (anchors, margins): ([Int], [Int])
            switch object.align {
            case 1: (anchors, margins) = ([0, 1, 1, 0], [0, b[1], right, 0])
            case 2: (anchors, margins) = ([1, 1, 1, 0], [b[0], b[1], right, 0])
            case 3: (anchors, margins) = ([0, 1, 0, 0], [b[0], b[1], right, 0])
            default: (anchors, margins) = ([1, 1, 0, 0], [b[0], b[1], 0, 0])
            }
            return Object(name: object.name, item: object.item, anchors: anchors, margins: margins,
                          size: CGSize(width: b[2] - b[0], height: b[3] - b[1]), z: z, kind: kind, font: object.setting("Font"),
                          textAlign: object.setting("TextAlign").flatMap { Int($0) },
                          orientation: object.setting("Orientation").flatMap { Int($0) })
        }
    }

    /// The playlist's fonts and colours (version 2: `[SKIN_WIDTHS]` `Switch_*`) and the tabs' font.
    func settings() -> Settings {
        guard isVersion2 else {
            // `[File]`: `FormDisableResizing` 0 lets the window be sized from its edges, never below
            // `FormMinW`×`FormMinH` (Hameleon: 540 px tall, its playlist's left panel laid out for it).
            // Held to a window's sensible bounds: a wild value would not convert back to `Int`.
            let side = { (key: String) in min(max(0, Int(ini["File", key] ?? "") ?? 0), Self.largestSide) }
            let least = CGSize(width: side("FormMinW"), height: side("FormMinH"))
            return Settings(sizingEdge: ini["File", "FormDisableResizing"] == "0" ? Self.sizingEdge : nil,
                            playlist: AIMPSkinAIMP3.playlistSettings(ini), activeTab: ini["TabCtrl", "ActiveTab"],
                            minimumSize: least == .zero ? nil : least)
        }
        var playlist: [String: String] = [:]
        for key in ["Nrm", "Act", "Sel", "BK", "ABK", "SBK"] { playlist[key] = ini["SKIN_WIDTHS", "switch_" + key] }
        return Settings(playlist: playlist, activeTab: ini["SKIN_FONTS", "activetab"])
    }

    /// The panel's size as the skin was saved: version 3's `ParentBounds`, else its picture's
    /// (the player's is `MainClient` over a state of `BottomDock`).
    private func panelSize(_ object: Placed) -> CGSize {
        if let size = object.parentSize { return size }
        guard object.item == "MainFrame" else { return images[object.item.lowercased() + ".img"]?.frameSize ?? .zero }
        let client = images["mainclient.img"]?.frameSize ?? .zero
        let dock = images["bottomdock.img"].map { $0.height > 1 && $0.height % 2 == 0 ? $0.height / 2 : $0.height } ?? 0
        return CGSize(width: client.width, height: client.height + CGFloat(dock))
    }

    // MARK: Layout

    /// The player's layout: version 3's `MainLayout.xml` (the playlist frame's `PlaylistLayout.xml`),
    /// which it must have and read, or version 2's fixed one.
    func mainLayout() throws -> [Layout] {
        let main = isVersion2 ? [Panel(control: "MainFrame", align: "top", level: "0"), Panel(control: "PlaylistFrame", align: "client", level: "0")]
            : try documents.throwing("MainLayout.xml", missing: "An AIMP 2 skin with no MainLayout.xml.", documents.items).map(Panel.init)
        return try main.map(layout)
    }

    /// `PlaylistLayout.xml`'s panels, which version 3 must have and read when its layout holds the
    /// playlist frame, or version 2's: tabs over the top panel when `TabCtrlIsUp`, under it otherwise.
    private func playlistLayout() throws -> [Panel] {
        guard isVersion2 else {
            return try documents.throwing("PlaylistLayout.xml", missing: "An AIMP 2 skin with no PlaylistLayout.xml.", documents.items)
                .map(Panel.init)
        }
        let tabsUp = ini["SKIN_WIDTHS", "tabctrlisup"] != "0"
        return [Panel(control: "TabCtrl", align: "top", level: tabsUp ? "0" : "1"),
                Panel(control: "TopPanel", align: "top", level: tabsUp ? "1" : "0"),
                Panel(control: "BottomPanel", align: "bottom", level: "0"),
                Panel(control: "Container", align: "client", level: "0")]
    }

    /// One of AIMP 2's layout items (`<item Align Level Control>`): the panel it places.
    struct Panel {
        var control: String?
        var align: String?
        var level: String?
        var items: [Panel] = []

        init(control: String?, align: String?, level: String?, items: [Panel] = []) {
            (self.control, self.align, self.level, self.items) = (control, align, level, items)
        }

        init(_ node: AIMPNode) {
            self.init(control: node["Control"], align: node["Align"], level: node["Level"], items: node.children("item").map(Panel.init))
        }
    }

    /// One AIMP 2 layout item as the model's layout: named after its panel, the playlist and its tabs
    /// dock sites, the player and the playlist frame groups of their parts.
    private func layout(_ panel: Panel) throws -> Layout {
        var layout = Layout(align: panel.align ?? "top", level: panel.level ?? "0", items: try panel.items.map(self.layout))
        switch panel.control {
        case "MainFrame":
            layout.name = "MainFrame"
            layout.items = [Layout(name: "MainClient", align: "top", level: "0"), Layout(name: "BottomDock", align: "top", level: "1")]
        case "EqualizerFrame":
            layout.name = "MainEquaFrame"
        case "PlaylistFrame":
            layout.name = "PlaylistFrame"
            let list = Layout(align: "client", level: "2", items: try playlistLayout().map(self.layout))
            layout.items = [("PlsBottomBar", "bottom", "0"), ("PlsLeftBar", "left", "1"), ("PlsRightBar", "right", "1")]
                .filter { images[$0.0.lowercased() + ".img"] != nil }
                .map { Layout(name: $0.0, align: $0.1, level: $0.2) } + [list]
        case let control?:
            layout.name = control
            layout.isDockSite = control == "Container" || control == "TabCtrl"
        case nil:
            break
        }
        return layout
    }
}
