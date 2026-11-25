import CoreGraphics

/// The playlist's vertical measures, which its layout (`AIMPSkinLayout.Rows`) and its painter both
/// read: AIMP's row is 4 px, the title's line, 2 px, the details' line and 2 px; AIMP 2's is its one
/// line and 4 px; a group's header band is its font and 13 px.
struct AIMPSkinPlaylistMetrics {
    static let above: CGFloat = 4
    static let between: CGFloat = 2
    static let below: CGFloat = 2
    static let classicPadding: CGFloat = 4
    static let headerPadding: CGFloat = 13

    /// A track's row and a header's band, at the list's normal fonts.
    let item: CGFloat
    let header: CGFloat

    init(_ style: AIMPSkinControl.Playlist) {
        let line = CGFloat(style.fonts[.normal]?.height ?? 13)
        item = style.classic ? line + Self.classicPadding
            : Self.above + line + Self.between + CGFloat(style.detailFonts[.normal]?.height ?? 11) + Self.below
        header = CGFloat(style.headerFont.height) + Self.headerPadding
    }

    /// The middle of a row's title line, the row at `top`, its title font `line` tall.
    static func titleMiddle(top: CGFloat, line: CGFloat) -> CGFloat { top + above + line / 2 }

    /// The middle of its details line, under the title.
    static func detailsMiddle(top: CGFloat, line: CGFloat, detail: CGFloat) -> CGFloat { top + above + line + between + detail / 2 }
}
