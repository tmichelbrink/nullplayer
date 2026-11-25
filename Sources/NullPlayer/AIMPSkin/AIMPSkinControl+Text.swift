import Foundation

extension AIMPSkinControl {
    /// What a key's caption or a display shows, and in what font, read once.
    struct Text: Sendable {
        /// Its `Font`, else its `Fonts`' `Normal`.
        let font: AIMPSkinFont
        let display: Display
        /// A `RunningLine` with nothing bound to it scrolls the playing track, by its `Template`;
        /// nil when a `DisplayValue` binding says what it shows.
        let running: String?
        /// `Alignment`, else `TextAlign`; whether `Alignment` (or a `TextAlign` not left) is there at
        /// all, and whether `Alignment` says `taLeftJustify`.
        let alignment: AIMPSkinTextAlign?
        let declaresAlignment: Bool
        let isLeftJustified: Bool
        /// `WordWrap`, or a `MultiLine` layout: it breaks into lines down from its top.
        let wraps: Bool
        /// `AutoSize` `csHeight`: as tall as its lines; and whether `AutoSize` is there at all.
        let sizesHeight: Bool
        let declaresAutoSize: Bool

        /// Where a display's text comes from.
        enum Display: Sendable {
            case none
            /// Its `Caption` (`@Lng:` strings filled in).
            case caption(String)
            /// Bound to nothing: its own `Template` (window titles, RealPlayer 11's skin-info lines).
            case template(String)
            /// A `FileInfo` binding: its `Template`, else the link's `TextFormat` (`%Title`).
            case file(String)
            /// A text provider (Sony Media Tower's file type, volume): its template over its inputs.
            case concatenation(inputs: [AIMPSkinLink], template: String)
            /// A number (the clock, the position): through a template, else as AIMP writes it.
            case number(AIMPSkinLink, template: String?)
        }
    }

    /// The playlist's `Resources`, in `.acs3`'s flat form (`ItemLine1FontPlaying`) or `.acs4`/`.acs5`'s
    /// nested one (`ItemLine1Fonts/Playing`).
    struct Playlist: Sendable {
        enum Row: String, Sendable, CaseIterable {
            case normal = "Normal", playing = "Playing", selected = "Selected", playingSelected = "PlayingSelected"
        }

        /// Its own background picture (GX-77's paper sheet), else its background colour.
        let picture: String?
        /// Its colours as the skin gives them, a value or a colour resource the painter reads through
        /// the theme's aliases (Sony Media Tower Reborn's white list, `Skin.FFFFFFFF`).
        let background: AIMPSkinColor?
        /// `ItemBackground`: a picture under every row (Sony Media Tower Reborn's white rows, its
        /// list's own colour black).
        let rowPicture: String?
        /// Each row's font and its fill (the normal row has none of its own).
        let fonts: [Row: AIMPSkinFont]
        let fills: [Row: AIMPSkinColor]
        /// AIMP's second line, the track's format and size (`ItemLine2Fonts`), by row state.
        let detailFonts: [Row: AIMPSkinFont]
        /// A group's header (`HeaderFonts`), its picture under it (`HeaderBackground`) and its
        /// expand button (`HeaderExpandButtons`: collapsed, expanded).
        let headerFont: AIMPSkinFont
        let headerPicture: String?
        let expandButtons: String?
        /// A track's rating marks (`ItemMarks`, earlier `SkinMarks`: unrated, rated), the switch beside
        /// each row (`ItemSwitches`, earlier `SkinSwitches`) and beside each header (`HeaderSwitches`).
        let marks: String?
        let switches: String?
        let headerSwitches: String?
    }

    /// The colours of the library's group tree and table (`Style` in `.acs4`, `StyleContent` in
    /// `.acs5`): the list's fill, the chosen row in `RowColorSelected` with `RowColorSelectedText`,
    /// text in `RowColorText` or `ColorText`. NullPlayer's library browser, hosted over the lists,
    /// wears them (`AIMPSkinLibraryHost`).
    struct Library: Equatable, Sendable {
        private(set) var fill: UInt32?
        private(set) var selected: UInt32?
        private(set) var selectedText: UInt32?
        private(set) var rowText: UInt32?
        /// The same four as the skin gives them, a value or a colour resource (M5's theme colours),
        /// for `resolved`.
        var sources: Sources
        struct Sources: Equatable, Sendable {
            let fill: AIMPSkinColor?, selected: AIMPSkinColor?, selectedText: AIMPSkinColor?, rowText: AIMPSkinColor?
        }

        /// The colours now, each read through `visible` (the theme's aliases; clear is none).
        func resolved(_ visible: (AIMPSkinColor?) -> UInt32?) -> Library {
            var library = self
            (library.fill, library.selected, library.selectedText, library.rowText) =
                (visible(sources.fill), visible(sources.selected), visible(sources.selectedText), visible(sources.rowText))
            return library
        }
    }

    /// NullPlayer's one playlist as the skin draws its tabs: AIMP 4's `TabControl` over
    /// `prvPlaylistManager` (or the library's), and `PlaylistTabs`.
    struct Tabs: Sendable {
        /// The manager a `TabControl` is bound to; one bound to neither is a picture.
        let source: String?
        /// `SkinTab` (or `TabSkin`), and `TabsOptions`' `Skin`.
        let picture: String?
        let optionsPicture: String?
        /// A `TabControl`'s caption font; `PlaylistTabs`' lit tab's, and while playing.
        let font: AIMPSkinFont
        let activeFont: AIMPSkinFont
        let playingFont: AIMPSkinFont
        /// `VerticalLayout`: a column of tabs.
        let isVertical: Bool
        /// `TextOffsetsActive` (l, t, r, b), and the caption centred unless `TextAlignment` says not.
        let offsets: AIMPSkinImage.Margins?
        let isCentred: Bool
    }
}

/// Where a line of text sits across its box: `Alignment` (`TextAlign` in `.acs3`) `taLeftJustify`,
/// `taCenter`, `taRightJustify`; nil for anything else, which reads from the left.
enum AIMPSkinTextAlign: Sendable {
    case left, center, right

    init?(_ value: String?) {
        switch value {
        case "taLeftJustify": self = .left
        case "taCenter": self = .center
        case "taRightJustify": self = .right
        default: return nil
        }
    }
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
