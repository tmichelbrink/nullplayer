import CoreGraphics
import Foundation

/// AIMP 2's `.acs` (`reference/format.md` § *AIMP 2*), read straight into the model through the
/// same `Shape` and `Build` as AIMP 3.0's skins: its `main.ini` gives AIMP 3.0's `Object`s and the
/// layout as typed `AIMPSkinAIMP3.Layout` items, with no AIMP 3.0 document between.
///
/// - **Panels.** An object's parent is a panel: `MAIN` the player (`MainClient` over the second
///   of `BottomDock`'s two stacked states, the one docked to the playlist), `EQ` the equalizer
///   (`MainEquaFrame`; version 2's `Client`), `TOP` and `BTM` the playlist's `TopPanel` and
///   `BottomPanel`, `ContainerN` a skin's own panel. The tray control (`TCCTRL`, `TCINFO`), quick
///   file info (`QFIClient`) and the detached playlist's title bar (`PlaylistFrame`, over
///   `PlsTopDock`) are AIMP's windows and are left out.
/// - **Layout.** Version 3 has `MainLayout.xml` and `PlaylistLayout.xml`: sibling `<item Align
///   Level Control>` elements, the `Control` a panel; the playlist frame holds the playlist
///   layout inside `PlsLeftBar`, `PlsRightBar` and `PlsBottomBar`. Version 2 has none: the
///   player over the playlist, its tabs (when `TabCtrlIsUp`), top panel, bottom panel and list.
///   An equalizer the layout leaves out (not all-in-one) is a window right of the player that
///   `EQBtn` opens (`[EquaForm]`).
/// - **Placement.** Version 3's object sections give `Bounds` (left, top, right, bottom in the
///   panel), `ParentBounds` (the panel when the skin was saved) and `Align`: 0 keeps the left
///   edge, 1 the right, 2 both (it stretches), 3 neither (it keeps its proportion). Version 2
///   keeps the bounds in `[SKIN_OBJS]`, the parents in `[PARENTS]` (none for the equalizer's
///   objects) and the rest as `[SKIN_WIDTHS]` `<Object>_align`, `_HORIZONTAL` and `Digits`,
///   `[SKIN_FONTS]` and `[SKIN_TEXTALIGNS]`. Unused objects have empty bounds.
/// - **Pictures** are `<Object>.bmp` (version 2: `<Object>_skin.bmp`), states side by side:
///   `SkinFrames` of them, else as many as fit the object's width (a digit strip's: its
///   `Digits`' width). A slider's lit track is `<Object>_sel`, its thumb `<Object>_thumb`. A
///   panel's `TLC` and `TRC` (version 2: `[SKIN_RECTS]` `<Panel>_TLC`) are the columns that
///   stretch, as `x1,0,x2,0`.
struct AIMPSkinAIMP2 {
    let documents: AIMPSkinDocuments
    let ini: INIFile
    /// The bitmaps by the names version 3 gives them: version 2's `_skin` dropped, its equalizer
    /// `Client` as `MainEquaFrame`; `SRINFO` reads `BRINFO`'s digits when it has none.
    let images: [String: AIMPSkinImage]
    /// Version 2's `main.ini` (`[SKIN_OBJS]`) has no layout files; version 3's has.
    let isVersion2: Bool
    /// The `.lng` strings its `@Lng:N;` captions read (`AIMPSkinLanguage`).
    let strings: [String: String]

    typealias Object = AIMPSkinAIMP3.Object
    typealias Layout = AIMPSkinAIMP3.Layout

    init(documents: AIMPSkinDocuments, ini: INIFile, images: [String: AIMPSkinImage], strings: [String: String] = [:]) {
        self.documents = documents
        self.ini = ini
        self.strings = strings
        isVersion2 = ini["SKIN_OBJS"] != nil
        let isVersion2 = isVersion2
        func stem(_ file: String) -> String {
            var stem = String(file.dropLast(4))
            if isVersion2, stem.hasSuffix("_skin") { stem = String(stem.dropLast(5)) }
            if isVersion2, stem == "client" { stem = "mainequaframe" }
            return stem
        }
        var renamed: [String: AIMPSkinImage] = [:]
        for (key, image) in images { renamed[stem(key) + ".img"] = image }
        // `links.system`: the skin editor's shared pictures, one object drawn with another's
        // (Hameleon's equalizer bands with `PreAmp`'s, its effect sliders with `Speed`'s, its
        // rating with `PlaylistRating`'s). A picture the skin ships itself wins.
        for (target, source) in Self.links(documents) {
            let key = stem(target) + ".img"
            if renamed[key] == nil, let image = renamed[stem(source) + ".img"] { renamed[key] = image }
        }
        if renamed["srinfo.img"] == nil { renamed["srinfo.img"] = renamed["brinfo.img"] }
        // The skin editor gives the equalizer's bands one picture, the ninth's (every version 2
        // skin has `AIMPSlider9_skin` and few another band's): a band with no picture of its own
        // takes the ninth's parts, but those it ships.
        for band in 1...18 where renamed["aimpslider\(band).img"] == nil {
            for part in ["", "_thumb", "_sel"] where renamed["aimpslider\(band)\(part).img"] == nil {
                renamed["aimpslider\(band)\(part).img"] = renamed["aimpslider9\(part).img"]
            }
        }
        self.images = renamed
    }

    /// `links.system`'s aliases, lowercased: 64-byte records, the picture an object draws with
    /// (32 bytes, NUL-padded, the Windows code page) and the picture it is (32 bytes).
    static func links(_ documents: AIMPSkinDocuments) -> [(target: String, source: String)] {
        guard let entry = documents.archive.entry("links.system") else { return [] }
        let data: Data
        do { data = try documents.archive.payload(entry) } catch {
            documents.record(error as? AIMPSkinFinding ?? AIMPSkinFinding(.entryUnreadable, "links.system: \(error)"))
            return []
        }
        let bytes = [UInt8](data)
        func name(_ range: Range<Int>) -> String {
            let used = bytes[range].prefix { $0 != 0 }
            return (String(bytes: used, encoding: .windowsCP1251) ?? String(decoding: used, as: UTF8.self)).lowercased()
        }
        return stride(from: 0, to: bytes.count - 63, by: 64).compactMap { start in
            let target = name(start..<(start + 32)), source = name((start + 32)..<(start + 64))
            guard target.hasSuffix(".bmp"), source.hasSuffix(".bmp") else { return nil }
            return (target, source)
        }
    }

    /// How near its edges a sizable AIMP 2 window is sized from, in skin pixels. The skin does not
    /// say and AIMP 2's own band is not known; 4 px is assumed.
    static let sizingEdge = "4"
    static let equalizerWindow = "EquaForm"

    /// The main form's index, the equalizer window beside it when the layout leaves it out, and the
    /// pictures as the forms lay them out.
    func read(dialect: AIMPSkinDialect) throws -> (index: AIMPSkinIndex, companions: [AIMPSkin.Companion], images: [String: AIMPSkinImage]) {
        var images = self.images
        let placed = classified(isVersion2 ? version2Objects() : version3Objects())
        let main = try mainLayout()
        func holds(_ name: String, _ items: [Layout]) -> Bool { items.contains { $0.name == name || holds(name, $0.items) } }
        layOut(&images, objects: placed, playlistDocked: holds("PlaylistFrame", main))
        let ownsEqualizer = !holds("MainEquaFrame", main) && images["mainequaframe.img"] != nil
        let settings = settings()
        var shape = AIMPSkinAIMP3.Shape(frame: { _ in nil }, images: images, objects: objects(placed), activeTab: settings.activeTab,
                                        playlist: settings.playlist)
        shape.equalizerWindow = ownsEqualizer ? Self.equalizerWindow : nil
        shape.playlistRoom = true
        // The main window's least size is its own: the equalizer window opens at what it holds.
        let form = shape.form(main, sizingEdge: settings.sizingEdge, minimumSize: settings.minimumSize)
        var companions: [(companion: AIMPSkin.Companion, root: AIMPSkinAIMP3.Shaped)] = []
        if ownsEqualizer {
            let equalizer = shape.form([Layout(name: "MainEquaFrame")], sizingEdge: settings.sizingEdge)
            companions.append((AIMPSkin.Companion(name: Self.equalizerWindow, title: "Equalizer", initiallyVisible: false, role: .other,
                                                  placement: .right), equalizer.root))
        }
        let index = AIMPSkinAIMP3.Build(shape: shape, dialect: dialect, strings: strings).index(form, companions: companions)
        return (index, companions.map(\.companion), images)
    }
}
