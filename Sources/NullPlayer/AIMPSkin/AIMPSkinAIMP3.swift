import CoreGraphics
import Foundation

/// AIMP 3.0 skins (`.acs3` kinds 1 and 2: Vega AIO, GREEX, Aero Style), read straight into the
/// model (`reference/format.md` § *AIMP 3.0*):
/// - `MainFrame.xml` (and `PlaylistFrame.xml`, `EqFrame.xml` for the dock sites that name them) is
///   the item tree, attribute style: `Class` `TAIMPLayoutContainerItem` (a picture named after the
///   item), `TAIMPLayoutTextureItem`, `TAIMPLayoutItem`, `TAIMPLayoutDockSiteItem`; `Align` (none is
///   top), `AlignLevel` (lower docks first), `AlignMargins`, `MinSize`, `MaxSize`.
/// - `main.ini` places the controls: `[Parents]` names each one's item, its own section its
///   `PlaceAnchors`, `PlaceMargins`, `PlaceWidth`/`PlaceHeight` and `ZOrder`. What a control is
///   comes from its name (AIMP's own objects: `PlayPauseBtn`, `VolumeBar`), `[Clones]` (a copy of
///   one) or `[CustomObjects]` (`ClassTextLabel`, `ClassNumLabel;4`). Its picture is `<name>.myimg`,
///   or `<name>.bmp` cut as its section says (`bitmapLayouts`).
/// Objects AIMP 3 parks left of or above their item (every unused one) are left out. Its colours are
/// Delphi's (`$00BBGGRR`). It has no scripts, providers or resources.
enum AIMPSkinAIMP3 {
    /// The main form, its index, read from the skin's layout documents and `main.ini`.
    static func read(_ documents: AIMPSkinDocuments, ini: INIFile, images: [String: AIMPSkinImage],
                     strings: [String: String] = [:], dialect: AIMPSkinDialect) throws -> AIMPSkinIndex {
        let layout = try documents.throwing("MainFrame.xml", missing: "An AIMP 3.0 skin with no MainFrame.xml.", documents.node)
        // A dock site's frame that does not read is a finding (`documents`), and the site is left as
        // if it had none.
        var shape = Shape(frame: { documents.node($0).map(Layout.items) }, images: images, objects: objects(ini),
                          activeTab: ini["TabCtrl", "ActiveTab"], playlist: playlistSettings(ini))
        let form = shape.form(Layout.items(of: layout), sizingEdge: ini["MainFrame", "SizingHitTestAreaWidth"])
        return Build(shape: shape, dialect: dialect, strings: strings).index(form)
    }

    /// How each BMP picture is cut, by lowercased object name: its `main.ini` section's `SkinFrames`,
    /// `SkinLayout` (1 stacked), `Margins` (left, top, right, bottom) and, when `StretchMode` is 1, the
    /// two stretched columns `TLC` and `TRC` (each `left, top, right, bottom`).
    static func bitmapLayouts(_ ini: INIFile) -> [String: AIMPSkinImage.Layout] {
        var layouts: [String: AIMPSkinImage.Layout] = [:]
        for section in ini.sections {
            var layout = AIMPSkinImage.Layout()
            layout.frames = max(1, Int(section["SkinFrames"] ?? "") ?? 1)
            layout.stacked = section["SkinLayout"] == "1"
            let m = AIMPNode.numbers(section["Margins"])
            if m.count == 4 { layout.margins = .init(left: m[0], top: m[1], right: m[2], bottom: m[3]) }
            let left = AIMPNode.numbers(section["TLC"]), right = AIMPNode.numbers(section["TRC"])
            if section["StretchMode"] == "1", left.count == 4, right.count == 4 {
                layout.columns = .init((left[0], left[2] - left[0]), (right[0], right[2] - right[0]))
            }
            layouts[section.name.lowercased()] = layout
        }
        return layouts
    }

    // MARK: - Layout documents

}

extension AIMPSkinAIMP3.Layout {
    /// A layout document's `<item>`s, as AIMP 3.0 writes them.
    static func items(of document: AIMPNode) -> [Self] {
        document.children("item").map(Self.init)
    }

    init(_ node: AIMPNode) {
        self.init(name: node["Name"], isDockSite: node["Class"] == "TAIMPLayoutDockSiteItem", align: node["Align"],
                  level: node["AlignLevel"], margins: node["AlignMargins"], minSize: node["MinSize"], maxSize: node["MaxSize"],
                  autoSize: node["AutoSize"], resizesByWidth: node["AllowResizeByWidth"], resizesByHeight: node["AllowResizeByHeight"],
                  items: Self.items(of: node))
    }
}

extension AIMPSkinAIMP3 {
    // MARK: - main.ini

    /// One object `main.ini` places.
    struct Object {
        let name: String
        /// The item it is placed in.
        let item: String
        /// AIMP 3's `PlaceInfo`: the edges it keeps (left, top, right, bottom), its distances from
        /// them, and its own size.
        let anchors: [Int]
        let margins: [Int]
        let size: CGSize
        /// Back to front.
        let z: Int
        let kind: Kind
        /// `Font`: `name,BGR,height,style`.
        let font: String?
        /// `TextAlign`: 0 left, 1 right, 2 centred.
        let textAlign: Int?
        /// A slider's `Orientation`: 0 upright, 1 across, 2 a knob turned through its frames.
        let orientation: Int?
    }

    /// What an object is: `[CustomObjects]`' class, else AIMP's own object its name names.
    enum Kind {
        /// `ClassTextLabel`: a caption, or a template of the playing file's tags (`%T`).
        case text(String)
        /// `ClassNumLabel;4`: the time in `digits` places, `indent` apart.
        case time(Time, digits: String, indent: String)
        /// `ClassNumLabel;5` and `;6`.
        case bitrate, sampleRate
        /// `ClassStatusLabel`: a picture per play state; `;2` shows the player's.
        case status(showsState: Bool)
        case seekBar
        /// `ClassAnimator`, a frame every `interval` ms.
        case animator(interval: String)
        /// `ClassSpectrum`: `peaks` bars `indent` apart in `colour` (Delphi), upside down when `flipped`.
        /// `masked`: `SkinHitTestMask` 1, the picture is the bars themselves (`control`).
        case spectrum(peaks: String, indent: String, colour: Int64?, flipped: Bool, masked: Bool)
        case coverArt
        /// `AIMPEQDisplay`: the curve's and the preamp line's colours (`EQVISE`, `EQVISL`, Delphi).
        case equalizerDisplay(curve: Int64?, preamp: Int64?)
        /// AIMP's own object (`playpausebtn`, `volumebar`), lowercased: the name, or through
        /// `[Clones]` the object it copies.
        case object(String)

        /// `sleepTimer`: AIMP's sleep timer, which NullPlayer does not have, so it reads zero as
        /// AIMP's does when off (GREEX's `00:00:00` under its clock).
        enum Time { case position, remaining, duration, sleepTimer }

        /// `custom` the `[CustomObjects]` class (`ClassNumLabel;4`), `base` the AIMP object the name
        /// is or copies, `setting` the object's own keys. Nil for a class NullPlayer does not draw.
        init?(custom: String?, base: String, setting: (String) -> String?) {
            let parts = custom?.split(separator: ";").map(String.init) ?? []
            switch parts.first {
            case "ClassTextLabel":
                guard let template = setting("Template"), !template.isEmpty else { return nil }
                self = .text(template)
            case "ClassNumLabel":
                switch parts.dropFirst().first {
                case "4":
                    let time: Time = setting("Static") == "1" ? .duration : setting("Reverse") == "1" ? .remaining : .position
                    self = .time(time, digits: setting("Digits") ?? "5", indent: setting("IndentBetweenDigits") ?? "0")
                case "1": self = .time(.sleepTimer, digits: setting("Digits") ?? "6", indent: setting("IndentBetweenDigits") ?? "0")
                case "5": self = .bitrate
                case "6": self = .sampleRate
                default: return nil
                }
            case "ClassStatusLabel": self = .status(showsState: parts.dropFirst().first == "2")
            case "ClassSeekBar": self = .seekBar
            case "ClassAnimator": self = .animator(interval: setting("AnimationInterval") ?? "50")
            case "ClassSpectrum":
                self = .spectrum(peaks: setting("Peaks") ?? "16", indent: setting("Indent") ?? "1",
                                 colour: setting("Color").flatMap { Int64($0) }, flipped: setting("Orientation") == "1",
                                 masked: setting("SkinHitTestMask") == "1")
            case "ClassCoverArt": self = .coverArt
            default:
                func colour(_ key: String) -> Int64? { setting(key).flatMap { UInt32($0) }.map(Int64.init) }
                switch base {
                case "aimpeqdisplay": self = .equalizerDisplay(curve: colour("EQVISE"), preamp: colour("EQVISL"))
                // AIMP's own sleep timer display, a digit strip like `ClassNumLabel;1`.
                case "sleeptime": self = .time(.sleepTimer, digits: setting("Digits") ?? "6", indent: setting("IndentBetweenDigits") ?? "0")
                default: self = .object(base)
                }
            }
        }
    }

    /// The objects, `[Parents]` in file order, each placed by its own section.
    static func objects(_ ini: INIFile) -> [Object] {
        let clones = Dictionary((ini["Clones"]?.lines ?? []).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        return (ini["Parents"]?.lines ?? []).compactMap { name, item in
            let own = ini[name]
            func setting(_ key: String) -> String? { own?[key] }
            // Held as the layout's numbers are (`AIMPNode.numbers`): a size near `Int.max` would
            // round past it as a `CGFloat` and trap where it is made whole again.
            func dimension(_ key: String) -> Int { min(max(Int(setting(key) ?? "") ?? 0, -1_000_000), 1_000_000) }
            guard let kind = Kind(custom: ini["CustomObjects", name], base: original(of: name, clones: clones), setting: setting) else {
                return nil
            }
            return Object(name: name, item: item,
                          anchors: AIMPNode.numbers(setting("PlaceAnchors") ?? "1,1,0,0"),
                          margins: AIMPNode.numbers(setting("PlaceMargins") ?? "0,0,0,0"),
                          size: CGSize(width: dimension("PlaceWidth"), height: dimension("PlaceHeight")),
                          z: Int(setting("ZOrder") ?? "") ?? 0, kind: kind, font: setting("Font"),
                          textAlign: setting("TextAlign").flatMap { Int($0) }, orientation: setting("Orientation").flatMap { Int($0) })
        }
    }

    /// The AIMP object `name` is, lowercased: itself, or through `clones` the object it copies (a
    /// copy of a copy too; a loop ends where it would come round).
    static func original(of name: String, clones: [String: String]) -> String {
        var base = name.lowercased()
        var seen: Set<String> = [base]
        while let next = clones[base]?.lowercased(), seen.insert(next).inserted { base = next }
        return base
    }

    /// `[Playlist]`'s fonts and colours, as AIMP 3 names them.
    static func playlistSettings(_ ini: INIFile) -> [String: String] {
        var found: [String: String] = [:]
        for key in ["Nrm", "Act", "Sel", "SelAct", "NrmHdr", "ActHdr", "SelHdr", "SelActHdr", "Header", "BK", "ABK", "SBK", "SABK"] {
            found[key] = ini["Playlist", key]
        }
        return found
    }
}
