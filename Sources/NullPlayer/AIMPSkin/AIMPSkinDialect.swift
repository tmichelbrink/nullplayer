import Foundation

/// What a skin's file format decides about reading it, taken once from its archive (`AIMPSkin.load`)
/// and held on its index, so no reader tests `archive.format` itself.
struct AIMPSkinDialect: Sendable, Equatable {
    /// A flat colour with no alpha is a Delphi colour, opaque (`.acs3`), rather than a clear ARGB one
    /// (`.acs4` on: Arc's playlist `BackgroundColor` `0`).
    var delphiColors: Bool

    /// `.acs4` and `.acs5`, and a project folder.
    static let modern = Self(delphiColors: false)

    init(delphiColors: Bool) {
        self.delphiColors = delphiColors
    }

    init(_ archive: AIMPSkinArchive) {
        self.init(delphiColors: archive.format == .acs3)
    }
}
