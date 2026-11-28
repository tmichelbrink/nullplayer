import CoreGraphics
import CoreText
import Foundation
import os

/// Fonts an AIMP skin ships in its own archive, for the faces it names: M5 draws its icons in the
/// `Segoe Fluent Icons` it ships, which unfound became a box. They are kept on the skin's own shelf
/// (`AIMPSkin.fontShelf`), never registered for the process, so a skin's Century Gothic does not become another
/// skin's or another family's. A face the system already has is never taken over: a skin must not
/// change what `Arial` means.
enum AIMPSkinFonts {

    /// The fonts one skin ships, by family and full name (`Segoe UI Variable`, `Poppins Medium`):
    /// AIMP's text finds them only on that skin's own shelf, passed to the font resolver, so M5's
    /// Segoe UI does not become the Segoe UI of a skin loaded after it (Bliss asks for it and ships none).
    final class Shelf: @unchecked Sendable {
        let id: Int
        let fonts: [String: CGFont]

        fileprivate init(id: Int, fonts: [String: CGFont]) {
            (self.id, self.fonts) = (id, fonts)
        }

        /// A font the skin ships, by family or full name.
        func font(named name: String) -> CGFont? { fonts[name.lowercased()] }
    }

    /// How many shelves have been made: each takes the next number as its `id`.
    private static let shelves = OSAllocatedUnfairLock(initialState: 0)

    /// A shelf of the fonts in `files` the system has no family of; nil when there are none.
    /// A family's name goes to its upright face, whichever file comes first: Segoe UI's Semibold
    /// file names its family "Segoe UI" too.
    static func shelf(_ files: [Data]) -> Shelf? {
        guard !files.isEmpty else { return nil }
        // Read for each shelf, not once: the user may enable or disable a family between two skins.
        let installed = installedFamilies()
        var fonts: [String: CGFont] = [:], uprights = Set<String>()
        for data in files {
            guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider) else { continue }
            let face = CTFontCreateWithGraphicsFont(font, 12, nil, nil)
            let family = (CTFontCopyFamilyName(face) as String).lowercased(), full = (CTFontCopyFullName(face) as String).lowercased()
            guard !installed.contains(family) else { continue }
            let upright = isUpright(face)
            if fonts[family] == nil || (upright && !uprights.contains(family)) { fonts[family] = font }
            if upright { uprights.insert(family) }
            if fonts[full] == nil { fonts[full] = font }
        }
        guard !fonts.isEmpty else { return nil }
        return Shelf(id: shelves.withLock { $0 += 1; return $0 }, fonts: fonts)
    }

    private static func isUpright(_ face: CTFont) -> Bool {
        CTFontGetSymbolicTraits(face).intersection([.traitBold, .traitItalic]).isEmpty
            && (CTFontCopyName(face, kCTFontStyleNameKey) as String?).map { ["regular", "normal", "book", "roman"].contains($0.lowercased()) } ?? true
    }

    /// The system's font families now, lowercased: a copy of hundreds of names, read once a shelf.
    private static func installedFamilies() -> Set<String> {
        Set((CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).map { $0.lowercased() })
    }
}

/// A skin font (`TASEFont`): its face, pixel height, weight and ARGB colour.
struct AIMPSkinFont: Equatable, Sendable {
    var name: String
    var height: Int
    var bold: Bool
    var color: UInt32
    /// The height is the letters' (Windows' negative `Height`: `Tahoma,…,-11,0`), not the line's.
    var emHeight = false
    /// `ColorID`: a colour resource it takes its colour from, through the aliases a theme script
    /// repointed (M5's text, `Skin.Color.Content.Text` light or dark), over `color`.
    var colorID: String? = nil
    /// The `TASEFont` resource it was read from, and what that gave, which a script may repoint
    /// (`resolved(in:links:)`).
    var resource: Resource? = nil

    struct Resource: Equatable, Sendable {
        let id: String
        let name: String
        let height: Int
        let bold: Bool
        let color: UInt32
        /// The settings the control declared over the resource itself: they stay when the resource
        /// is repointed, even where they equal what it gave.
        var declared: Settings = []
    }

    /// A font's `Name`, `Height`, `Style` and `Color` settings.
    struct Settings: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let name = Settings(rawValue: 1 << 0)
        static let height = Settings(rawValue: 1 << 1)
        static let style = Settings(rawValue: 1 << 2)
        static let color = Settings(rawValue: 1 << 3)
    }

    /// As drawn, through the resource aliases a script repointed (M5's and Soot's themes): what the
    /// resource gave comes from the one it now names; what the skin set over it stays.
    func resolved(in resources: [String: AIMPSkinResource], links: [String: String]) -> AIMPSkinFont {
        var font = self
        if let resource, !links.isEmpty, let chain = AIMPSkin.resource(resource.id, in: resources, links: links)?.chain, !chain.isEmpty {
            let now = AIMPSkinFont(resource: chain)
            let declared = resource.declared
            if name == resource.name, !declared.contains(.name) { font.name = now.name }
            if height == resource.height, !declared.contains(.height) { font.height = now.height }
            if bold == resource.bold, !declared.contains(.style) { font.bold = now.bold }
            if color == resource.color, !declared.contains(.color) { font.color = now.color }
            if colorID == nil { font.colorID = now.colorID }
        }
        if let id = font.colorID, let argb = AIMPSkin.color(id, in: resources, links: links) { font.color = argb }
        return font
    }

    /// The face at AIMP's pixel height, bold when asked; one neither the Mac nor the skin has
    /// (`Segoe UI`) falls back to the system font. A height is Windows': a line's, ascent
    /// and descent, unless `emHeight`; so the letters' size is the face's own share of it (Poppins
    /// 0.57, Segoe UI 0.75, Tahoma 0.83: M5's "NOW PLAYING" in its 88-px box). Never below 8. Made
    /// once per face, height and weight: text is set many times a frame. `shelf` is the fonts the
    /// skin being drawn ships (`AIMPSkin.fontShelf`).
    func ctFont(on shelf: AIMPSkinFonts.Shelf?) -> CTFont {
        let key = Face(name: name, height: height, emHeight: emHeight, bold: bold, shelf: shelf?.id ?? 0)
        if let made = Self.faces.withLockUnchecked({ $0[key] }) { return made }
        let sample = Self.face(name, size: 100, bold: bold, shelf: shelf)
        // A face the Mac stands in for (`Segoe UI` on most Macs) keeps AIMP's usual share, 0.8: its
        // own line says nothing of the face the skin was drawn with.
        let line = sample.found ? Self.windowsLine(sample.font) ?? (CTFontGetAscent(sample.font) + CTFontGetDescent(sample.font)) / 100 : 1.25
        let size = max(8, (emHeight || line <= 0 ? CGFloat(height) : CGFloat(height) / line).rounded())
        let face = Self.face(name, size: size, bold: bold, shelf: shelf).font
        Self.faces.withLockUnchecked { faces in
            // Every load of a skin with fonts makes a new shelf, and a face made from one holds its
            // font data: past `faceLimit` the faces are let go and made again as drawn.
            // Other shelves' faces go first (skins since reloaded); only then the rest.
            if faces.count >= Self.faceLimit { faces = faces.filter { $0.key.shelf == key.shelf } }
            if faces.count >= Self.faceLimit { faces.removeAll(keepingCapacity: true) }
            faces[key] = face
        }
        return face
    }

    /// `name`, a family or a family and weight (`Segoe UI Semibold`: Segoe UI, bold); else the
    /// system font.
    private static func face(_ name: String, size: CGFloat, bold: Bool, shelf: AIMPSkinFonts.Shelf?) -> (font: CTFont, found: Bool) {
        // A face the skin ships, bold from its own bold or semibold file: a lone shipped face cannot
        // be made bold, so a bold ask without one is the Mac's to answer (Bliss's bold Segoe UI rows).
        func shipped(_ name: String, _ bold: Bool) -> CTFont? {
            let names = bold ? [name + " bold", name + " semibold", name] : [name]
            guard let font = names.lazy.compactMap({ shelf?.font(named: $0) }).first else { return nil }
            let face = CTFontCreateWithGraphicsFont(font, size, nil, nil)
            let weight = (CTFontCopyTraits(face) as? [CFString: Any])?[kCTFontWeightTrait] as? CGFloat ?? 0
            return !bold || CTFontGetSymbolicTraits(face).contains(.traitBold) || weight > 0.2 ? face : nil
        }
        func family(_ name: String, _ bold: Bool) -> CTFont? {
            if let face = shipped(name, bold) { return face }
            let font = CTFontCreateWithName(name as CFString, size, nil)
            guard (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(name) == .orderedSame else { return nil }
            return bold ? CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) ?? font : font
        }
        if let font = family(name, bold) { return (font, true) }
        for (suffix, heavy) in [(" Semibold", true), (" SemiBold", true), (" Bold", true), (" Medium", false), (" Light", false)]
        where name.hasSuffix(suffix) {
            if let font = family(String(name.dropLast(suffix.count)), bold || heavy) { return (font, true) }
        }
        let system = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        return (system ?? CTFontCreateWithName(name as CFString, size, nil), false)
    }

    /// The line Windows sets a face in, per em: its `OS/2` `usWinAscent` and `usWinDescent` over
    /// its `head`'s units per em (Poppins 1.76 where its Mac line is 1.40); nil without them.
    private static func windowsLine(_ font: CTFont) -> CGFloat? {
        guard let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
              let head = CTFontCopyTable(font, CTFontTableTag(kCTFontTableHead), []) as Data?,
              os2.count >= 78, head.count >= 20 else { return nil }
        func u16(_ data: Data, _ at: Int) -> Int { Int(data[data.startIndex + at]) << 8 | Int(data[data.startIndex + at + 1]) }
        let units = u16(head, 18)
        guard units > 0 else { return nil }
        let line = CGFloat(u16(os2, 74) + u16(os2, 76)) / CGFloat(units)
        return line > 0 ? line : nil
    }

    private struct Face: Hashable {
        let name: String
        let height: Int
        let emHeight: Bool
        let bold: Bool
        /// The skin's own fonts it was looked up among (`AIMPSkinFonts.Shelf.id`), 0 for none.
        let shelf: Int
    }

    /// The faces made, shared by every skin (CTFont is immutable and safe across threads).
    private static let faces = OSAllocatedUnfairLock<[Face: CTFont]>(uncheckedState: [:])
    /// More faces than a few skins' text sets (M5 sets a few dozen), so a skin drawn keeps its own.
    private static let faceLimit = 512
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

    /// A font resource from its `chain` (`AIMPSkin.resource`): each `Resource` over the one it names,
    /// and what none says AIMP's for a resource.
    init(resource chain: [AIMPSkinResource.Entry]) {
        self = chain.reduce(AIMPSkinFont(name: "", height: 12, bold: false, color: 0xFFFF_FFFF)) {
            AIMPSkinFont(declared: $1.font, over: $0, clearIsDelphi: false)
        }
        if name.isEmpty { name = Self.standard.name }
    }

    /// `Name`, `Height`, `Style` and `Color` where `node` declares them, over `base`; a colour is
    /// ARGB, or, `clearIsDelphi` (a form's own fonts), with no alpha a Delphi colour (`66051`: near
    /// black), opaque.
    init(declared declaration: Declaration, over base: AIMPSkinFont, clearIsDelphi: Bool) {
        self = base
        let declared = declaration.values
        if let name = declared["Name"], !name.isEmpty { self.name = name }
        // `Int.min` has no magnitude `abs` can give.
        if let height = declared["Height"].flatMap(Int.init), height != .min {
            self.height = abs(height)
            emHeight = height < 0
        }
        if let style = declared["Style"] { bold = style.contains("fsBold") }
        if let id = declaration.colorID, !id.isEmpty { colorID = id }
        if let number = declared["Color"].flatMap({ Int64($0) }) {
            let argb = UInt32(truncatingIfNeeded: number)
            color = clearIsDelphi && argb >> 24 == 0 ? AIMPSkinColor.argb(delphi: number) : argb
        }
    }
}
