import Foundation

/// The fonts a WMP skin ships in its archive, registered for this process (`SkinFonts`).
enum WMPSkinFonts {
    static func register(from archive: WMPResourceProviding) {
        for path in archive.resourcePaths {
            let lower = path.lowercased()
            guard lower.hasSuffix(".ttf") || lower.hasSuffix(".otf"), let data = try? archive.data(for: path) else { continue }
            SkinFonts.register(data)
        }
    }
}
