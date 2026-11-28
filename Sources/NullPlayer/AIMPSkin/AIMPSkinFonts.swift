import CoreGraphics
import CoreText
import Foundation

/// Fonts an AIMP skin ships in its own archive, for the faces it names: M5 draws its icons in the
/// `Segoe Fluent Icons` it ships, which unfound became a box. They are kept on the skin's own shelf
/// (`AIMPSkin.fontShelf`), never registered for the process, so a skin's Century Gothic does not become another
/// skin's or another family's. A face the system already has is never taken over: a skin must not
/// change what `Arial` means.
enum AIMPSkinFonts {
    private static let lock = NSLock()

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

    private static var shelves = 0

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
        return Shelf(id: lock.withLock { shelves += 1; return shelves }, fonts: fonts)
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
