import Foundation

/// What a skin's file format decides about reading and laying it out, taken once from its archive
/// (`AIMPSkin.load`) and held on its index, so no reader tests `archive.format` itself.
struct AIMPSkinDialect: Sendable, Equatable {
    /// A flat colour with no alpha is a Delphi colour, opaque (`.acs3`, AIMP 2's settings), rather
    /// than a clear ARGB one (`.acs4` on: Arc's playlist `BackgroundColor` `0`).
    var delphiColors: Bool
    /// The playlist is AIMP 2's, one line a track and no group headers: AIMP 5.40 does not open an
    /// AIMP 2 skin, so NullPlayer keeps the list it has drawn them with.
    var classicPlaylist: Bool
    /// The opening window leaves out what the skin's own state hides (`AIMPSkinLayout`'s
    /// `hiddenBySkinState`). Not for a skin NullPlayer translated (AIMP 3.0's and AIMP 2's): its
    /// bindings are the translation's, not the skin's. An `.acs3` file holding an AIMP 4 form does.
    var sizesBySkinState: Bool
    /// A list the main form holds itself opens at its `SizeMinimal` (`AIMPSkinRenderer`). Not an
    /// AIMP 3.0 skin's, translated by NullPlayer: AIMP 5.40 opens it at what its other parts take.
    /// An `.acs3` file holding an AIMP 4 form keeps it (Gilly AIO, Electro, Lotex), as does an
    /// AIMP 2 skin, which AIMP 5.40 does not open.
    var listKeepsRoom: Bool

    /// `.acs4` and `.acs5`, and a project folder.
    static let modern = Self(delphiColors: false, classicPlaylist: false, sizesBySkinState: true, listKeepsRoom: true)

    init(delphiColors: Bool, classicPlaylist: Bool, sizesBySkinState: Bool, listKeepsRoom: Bool) {
        (self.delphiColors, self.classicPlaylist, self.sizesBySkinState, self.listKeepsRoom)
            = (delphiColors, classicPlaylist, sizesBySkinState, listKeepsRoom)
    }

    init(_ archive: AIMPSkinArchive) {
        let format = archive.format
        self.init(delphiColors: format == .acs3 || format == .acsp, classicPlaylist: format == .acsp,
                  sizesBySkinState: !archive.isLegacy, listKeepsRoom: !(archive.isLegacy && format == .acs3))
    }
}
