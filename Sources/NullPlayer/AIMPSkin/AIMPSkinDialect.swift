import Foundation

/// What a skin's file format decides about reading and laying it out, taken once from its archive
/// (`AIMPSkin.load`) and held on its index, so no reader tests `archive.format` itself.
struct AIMPSkinDialect: Sendable, Equatable {
    /// A flat colour with no alpha is a Delphi colour, opaque (`.acs3`), rather than a clear ARGB one
    /// (`.acs4` on: Arc's playlist `BackgroundColor` `0`).
    var delphiColors: Bool
    /// The opening window leaves out what the skin's own state hides (`AIMPSkinLayout`'s
    /// `hiddenBySkinState`). Not for an AIMP 3.0 skin (`AIMPSkinAIMP3`): its bindings are the
    /// reader's, not the skin's. An `.acs3` file holding an AIMP 4 form does.
    var sizesBySkinState: Bool
    /// A list the main form holds itself opens at its `SizeMinimal` (`AIMPSkinRenderer`). Not an
    /// AIMP 3.0 skin's: AIMP 5.40 opens it at what its other parts take (Bloom's list, 0 px under its
    /// tab row). An `.acs3` file holding an AIMP 4 form keeps it (Gilly AIO, Electro, Lotex).
    var listKeepsRoom: Bool
    /// A control belongs to the window, not to its item (`AIMPSkinLayout.controls(of:in:)`): it shows
    /// outside its item, and a cover is not cut at the item's edge. AIMP 3.0's, placed by `main.ini`
    /// (Vega AIO's equalizer, right of its panel, shows as the window widens); AIMP 4 and 5's are
    /// windows inside their item's.
    var controlsOutliveItems: Bool

    /// `.acs4` and `.acs5`, and a project folder.
    static let modern = Self(delphiColors: false)

    init(delphiColors: Bool, sizesBySkinState: Bool = true, listKeepsRoom: Bool = true, controlsOutliveItems: Bool = false) {
        (self.delphiColors, self.sizesBySkinState, self.listKeepsRoom, self.controlsOutliveItems)
            = (delphiColors, sizesBySkinState, listKeepsRoom, controlsOutliveItems)
    }

    init(_ archive: AIMPSkinArchive) {
        let aimp30 = archive.mainINI != nil
        self.init(delphiColors: archive.format == .acs3, sizesBySkinState: !aimp30, listKeepsRoom: !aimp30,
                  controlsOutliveItems: aimp30)
    }
}
