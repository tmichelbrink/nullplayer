import Foundation

/// What a skin's file format decides about reading and laying it out, taken once from its archive
/// (`AIMPSkin.load`) and held on its index, so no reader tests `archive.format` itself.
struct AIMPSkinDialect: Sendable, Equatable {
    /// A flat colour with no alpha is a Delphi colour, opaque (`.acs3`), rather than a clear ARGB one
    /// (`.acs4` on: Arc's playlist `BackgroundColor` `0`).
    var delphiColors: Bool
    /// The playlist is AIMP 2's, one line a track and no group headers: AIMP 5.40 does not open an
    /// AIMP 2 skin, so NullPlayer keeps the list it has drawn them with.
    var classicPlaylist: Bool
    /// The opening window leaves out what the skin's own state hides (`AIMPSkinLayout`'s
    /// `hiddenBySkinState`). Not for an AIMP 3.0 skin (`AIMPSkinAIMP3`): its bindings are the
    /// reader's, not the skin's. An `.acs3` file holding an AIMP 4 form does.
    var sizesBySkinState: Bool
    /// A list the main form holds itself opens at its `SizeMinimal` (`AIMPSkinRenderer`). Not an
    /// AIMP 3.0 skin's: AIMP 5.40 opens it at what its other parts take (Bloom's list, 0 px under its
    /// tab row). An `.acs3` file holding an AIMP 4 form keeps it (Gilly AIO, Electro, Lotex), as does
    /// an AIMP 2 skin, which AIMP 5.40 does not open.
    var listKeepsRoom: Bool
    /// A control belongs to the window, not to its item (`AIMPSkinLayout.controls(of:in:)`): it shows
    /// outside its item, and a cover is not cut at the item's edge. AIMP 3.0's and AIMP 2's, placed by `main.ini`
    /// (Vega AIO's equalizer, right of its panel, shows as the window widens); AIMP 4 and 5's are
    /// windows inside their item's.
    var controlsOutliveItems: Bool
    /// A window keeps the width its skin gives it, sized by height alone. AIMP 2.61 does so: Hameleon
    /// All-In-One's 624-px window and Euphoria Remix (All-In-One)'s 628-px one only grow down, into
    /// their playlist, and their equalizer panels have no stretching columns to widen by.
    var windowWidthFixed: Bool

    /// `.acs4` and `.acs5`, and a project folder.
    static let modern = Self(delphiColors: false)

    init(delphiColors: Bool, classicPlaylist: Bool = false, sizesBySkinState: Bool = true, listKeepsRoom: Bool = true,
         controlsOutliveItems: Bool = false, windowWidthFixed: Bool = false) {
        (self.delphiColors, self.classicPlaylist, self.sizesBySkinState, self.listKeepsRoom, self.controlsOutliveItems)
            = (delphiColors, classicPlaylist, sizesBySkinState, listKeepsRoom, controlsOutliveItems)
        self.windowWidthFixed = windowWidthFixed
    }

    init(_ archive: AIMPSkinArchive) {
        let format = archive.format, fromINI = archive.mainINI != nil
        self.init(delphiColors: format == .acs3 || format == .acsp, classicPlaylist: format == .acsp, sizesBySkinState: !fromINI,
                  listKeepsRoom: !(fromINI && format == .acs3), controlsOutliveItems: fromINI, windowWidthFixed: format == .acsp)
    }
}
