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

            /// What a control shows, whichever format wrote it: its `Caption`; else a `FileInfo`
            /// binding through its `Template` (else the link's `TextFormat`); else a text provider
            /// bound to `DisplayValue`, else the bound number through a template; else its own
            /// `Template`. `@Lng:` strings inside any are filled in (`Akai GX-635D - @Lng:10;`, Red
            /// Bias's `@Lng:15; %PlayCount`: "Played: 3").
            static func resolve(caption: String?, template: String?, bindings: AIMPSkinBindings, index: AIMPSkinIndex) -> Display {
                func expanded(_ text: String) -> String { AIMPSkinLanguage.expanded(text, strings: index.strings) }
                if let caption { return .caption(expanded(caption)) }
                if let file = bindings.links.first(where: { $0.pin == "FileInfo" && $0.target == "DisplayValue" }) {
                    return .file(expanded(template ?? file.textFormat ?? "%T"))
                }
                if let link = bindings["DisplayValue"] {
                    if let source = link.source, let provider = index.providers[source], provider.kind == .concatenator {
                        // No `Expression`: its first input's text.
                        return .concatenation(inputs: provider.bindings.links, template: expanded(provider.template ?? "%TextValue1"))
                    }
                    // A template over the bound number (`%time(MS;:;)`).
                    return .number(link, template: (template ?? link.textFormat).map(expanded))
                }
                return template.map { .template(expanded($0)) } ?? .none
            }
        }

        /// What a `RunningLine` with nothing bound to its `DisplayValue` scrolls: its `Template`,
        /// else the playing track (`running`).
        static func running(template: String?, bindings: AIMPSkinBindings, index: AIMPSkinIndex) -> String? {
            guard bindings["DisplayValue"] == nil else { return nil }
            return template.map { AIMPSkinLanguage.expanded($0, strings: index.strings) } ?? "%IF(%R,%R - ,)%T"
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
        /// AIMP 2's list: one line a track, no group headers (`AIMPSkinDialect.classicPlaylist`).
        var classic = false

        /// Each row's font, its second line's and the header's, from what the skin declares
        /// (`declared(state, line)`, `line` `ItemLine1`, `ItemLine2` or `Header`), whichever format
        /// wrote it. A row with none of its own takes the normal one's, over the list's own default,
        /// Tahoma 13; with none of its own, the second line is the first's font, smaller.
        static func fonts(_ declared: (_ state: String, _ line: String) -> AIMPSkinFont?)
            -> (rows: [Row: AIMPSkinFont], details: [Row: AIMPSkinFont], header: AIMPSkinFont) {
            let normal = declared("Normal", "ItemLine1") ?? AIMPSkinFont(name: "Tahoma", height: 13, bold: false, color: 0xFFC0_C0C0)
            var small = normal
            small.height = max(9, normal.height - 2)
            let detail = declared("Normal", "ItemLine2") ?? small
            return (Dictionary(uniqueKeysWithValues: Row.allCases.map { ($0, declared($0.rawValue, "ItemLine1") ?? normal) }),
                    Dictionary(uniqueKeysWithValues: Row.allCases.map { ($0, declared($0.rawValue, "ItemLine2") ?? detail) }),
                    declared("Normal", "Header") ?? normal)
        }
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
