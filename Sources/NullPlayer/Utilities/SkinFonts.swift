import CoreGraphics
import CoreText
import Foundation

/// Fonts a skin ships in its own archive, for the faces it names.
///
/// `Alpine7618_v09` names `fontFace="Quartz"` on every LCD readout and ships `Quartz.TTF` beside
/// them; M5 draws its icons in the `Segoe Fluent Icons` it ships. Unfound, `CTFontCreateWithName`
/// silently answers another face (Helvetica's widths, a box for an icon). WMP's are registered for
/// the process (`register`); AIMP's are kept on the skin's own shelf (`shelf`), so a skin's
/// Century Gothic does not become another family's. A face the system already has is never taken
/// over: a skin must not change what `Arial` means.
enum SkinFonts {
    private static let lock = NSLock()
    private static var registered = Set<String>()

    /// Registers the font in `data` unless the system has its family or it is registered already;
    /// true when it was registered now.
    @discardableResult
    static func register(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return false }
        lock.lock(); defer { lock.unlock() }
        let family = familyName(font)
        guard !registered.contains(name), !isInstalled(family) else { return false }
        guard CTFontManagerRegisterGraphicsFont(font, nil) else { return false }
        registered.insert(name)
        installed?.insert(family.lowercased())
        return true
    }

    /// The fonts one skin ships, by family and full name (`Segoe UI Variable`, `Poppins Medium`):
    /// AIMP's text finds them only while that skin is drawn (`shelf`), so M5's Segoe UI does not
    /// become the Segoe UI of a skin loaded after it (Bliss asks for it and ships none).
    final class Shelf: @unchecked Sendable {
        let id: Int
        let fonts: [String: CGFont]

        fileprivate init(id: Int, fonts: [String: CGFont]) {
            (self.id, self.fonts) = (id, fonts)
        }
    }

    /// The shelf of the skin being drawn (`AIMPSkin.withFonts`).
    @TaskLocal static var shelf: Shelf?
    private static var shelves = 0

    /// A shelf of the fonts in `files` the system has no family of; nil when there are none.
    /// A family's name goes to its upright face, whichever file comes first: Segoe UI's Semibold
    /// file names its family "Segoe UI" too.
    static func shelf(_ files: [Data]) -> Shelf? {
        var fonts: [String: CGFont] = [:], uprights = Set<String>()
        for data in files {
            guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider) else { continue }
            let face = CTFontCreateWithGraphicsFont(font, 12, nil, nil)
            let family = (CTFontCopyFamilyName(face) as String).lowercased(), full = (CTFontCopyFullName(face) as String).lowercased()
            guard lock.withLock({ !isInstalled(family) }) else { continue }
            let upright = isUpright(face)
            if fonts[family] == nil || (upright && !uprights.contains(family)) { fonts[family] = font }
            if upright { uprights.insert(family) }
            if fonts[full] == nil { fonts[full] = font }
        }
        guard !fonts.isEmpty else { return nil }
        return Shelf(id: lock.withLock { shelves += 1; return shelves }, fonts: fonts)
    }

    /// A font the skin being drawn ships, by family or full name.
    static func bundled(named name: String) -> CGFont? { shelf?.fonts[name.lowercased()] }

    private static func isUpright(_ face: CTFont) -> Bool {
        CTFontGetSymbolicTraits(face).intersection([.traitBold, .traitItalic]).isEmpty
            && (CTFontCopyName(face, kCTFontStyleNameKey) as String?).map { ["regular", "normal", "book", "roman"].contains($0.lowercased()) } ?? true
    }

    /// The system's font families, lowercased: read once (a copy of hundreds of names), with the
    /// ones `register` adds. Under `lock`.
    private static var installed: Set<String>?

    private static func familyName(_ font: CGFont) -> String {
        CTFontCopyFamilyName(CTFontCreateWithGraphicsFont(font, 12, nil, nil)) as String
    }

    /// Whether the system has `family`. Under `lock`.
    private static func isInstalled(_ family: String) -> Bool {
        if installed == nil {
            installed = Set((CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).map { $0.lowercased() })
        }
        return installed?.contains(family.lowercased()) == true
    }
}
