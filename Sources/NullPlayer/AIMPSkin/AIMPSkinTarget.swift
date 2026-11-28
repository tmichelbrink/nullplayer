import CoreGraphics
import CoreText
import Foundation

/// The pointer's effect on one frame: the control under it and the one held down.
struct AIMPSkinInteraction: Equatable, Sendable {
    var hovered: AIMPSkinControl.ID?
    var pressed: AIMPSkinControl.ID?
}

/// Something on screen the pointer can work: a control's rect in skin pixels and what it does.
struct AIMPSkinTarget: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// An AIMP action (`acPlayerPlay`), carried out by the window or the player.
        case action(AIMPAction)
        /// Runs the skin's `OnClick` event handler with this control as `Sender`.
        case handler(String)
        /// Runs `down` when pressed, with the pointer's place in the control as `Arguments` `X` and
        /// `Y`, and `up` when released, wherever the pointer is then. GX-R60's and the Onkyos' REW and
        /// FF wind while held (the handlers switch a seek timer on and off); a click on SL-1200's
        /// record drops the needle at that groove.
        case hold(down: String, up: String?)
        /// Opens a menu: NullPlayer's like the one a key's `PopupMenu` names (`pmEqualizer`: the
        /// presets), else the player's.
        case menu(AIMPSkinPopup?)
        /// A playlist or library window's own maximize key: the window fills its screen, and back.
        case maximize
        /// Sets a counter's position: the step over the current one, wrapped by its `Module`.
        case counter(name: String, step: AIMPSkinStep)
        /// Shows or hides a layout item (Cassette-3D's VU meter panel).
        case toggle(item: String)
        /// Sets a provider to a fixed value, 0–1 (Vega's balance left/centre/right keys).
        case setValue(provider: AIMPSkinProvider, value: Double)
        /// Sets a tabbed group's page: the step over the current page, wrapped to its tab count.
        case page(group: String, step: AIMPSkinStep)
        /// A slider over a data provider (`prvVolume`), dragged along its long side.
        case slider(provider: AIMPSkinProvider?, vertical: Bool)
        /// A filmstrip knob over a data provider, turned by dragging.
        case knob(provider: AIMPSkinProvider?)
        /// A skin's own playlist: its rows in view, down from the top of the rect, positions in the
        /// rows the quick search leaves. A click selects a row, a double click plays it, the wheel
        /// scrolls.
        case playlist(AIMPSkinLayout.Rows)
        /// A list's quick search box ("Playlist", "MLTable", "MLGroupingTree"): a click types into it.
        case search(list: AIMPSkinList)
        /// The library's group tree or table, in the skin's list colours: NullPlayer's library
        /// browser sits over it (`AIMPSkinLibraryHost`) and takes its clicks.
        case libraryArea(AIMPSkinControl.Library)
        /// The playlist's scroll bar: a press or drag puts the thumb (`thumb` px long) under the
        /// pointer, scrolling to that share of `maxTop`, the last row that can be at the top.
        case playlistScroll(maxTop: Int, thumb: CGFloat)
        /// A scroll view (`view`), over all it shows, which the wheel scrolls; or its scroll bar
        /// (`thumb` > 0), whose thumb a press or drag puts under the pointer. `maxTop` px of it can
        /// scroll out of sight.
        case viewScroll(view: String, maxTop: CGFloat, thumb: CGFloat)
        case seek

        /// Moved by dragging: a knob, slider or seek bar.
        var isDraggable: Bool {
            switch self {
            case .knob, .slider, .seek: return true
            default: return false
            }
        }

        /// A key a press on may become a drag of the knob or slider under it, once the pointer moves.
        var passesDragsThrough: Bool {
            switch self {
            case .action, .menu, .maximize: return true
            default: return false
            }
        }
    }

    /// The control it is on, and its name: what a script's handler gets as `Sender`.
    let control: AIMPSkinControl.ID
    let name: String
    let kind: Kind
    let rect: CGRect
    /// The button's hit mask, at the rect's size: a click on a transparent pixel of it falls through
    /// (Pioneer CT-F1000 draws REW and FF as two halves of one rect).
    var mask: AIMPAlphaMask? = nil
    /// A button's picture as drawn: where it is see-through, a click goes to a key under it
    /// (Bento's logo, a 68-px About key whose left 39 px are clear over its OPT key).
    var pixels: AIMPAlphaMask? = nil
    /// Where it can be hit, when a scroll view shows only part of it.
    var visibleRect: CGRect? = nil
    /// What it repeats while held (`ActionOnHold`: PREV and NEXT wind, VOLUME − and + step).
    var holdAction: AIMPAction?
    /// The skin counter a long press sets, and to what (`ActionOnLongClick`).
    var longClick: LongClick?
    struct LongClick: Equatable, Sendable {
        let counter: String
        let value: Int
    }
    /// The skin handler a key runs when let go (`OnMouseUp`), whatever else it does.
    var releaseHandler: String?
    /// What a right-click does instead of the menu (`ContextMenu`): a knob back to its middle
    /// (the Akais' bass and treble to 60), the balance keys to centre, an action.
    var rightClick: Kind?
    /// What the wheel does over it, where that is not what a press does (Soot's play/pause steps
    /// its volume counter on the wheel and runs its handlers on a click).
    var wheel: Kind?

    init(control: AIMPSkinControl.ID, name: String, kind: Kind, rect: CGRect, mask: AIMPAlphaMask? = nil) {
        self.control = control
        self.name = name
        self.kind = kind
        self.rect = rect
        self.mask = mask
    }

    /// Whether `point` (skin pixels) hits this target: inside its rect, on a drawn pixel. A mask of
    /// another size than the rect is sampled as the picture is drawn stretched over it, so the clear
    /// part of a stretched control is not clickable.
    func hit(_ point: CGPoint) -> Bool {
        guard rect.contains(point), visibleRect?.contains(point) ?? true else { return false }
        guard let mask, mask.width > 0, mask.height > 0, rect.width > 0, rect.height > 0 else { return true }
        let x = Int((point.x - rect.minX) * CGFloat(mask.width) / rect.width)
        let y = Int((point.y - rect.minY) * CGFloat(mask.height) / rect.height)
        return mask.covers(min(x, mask.width - 1), min(y, mask.height - 1))
    }

    /// Of `targets` (topmost last), the one a click at `point` reaches: the topmost hit, unless its
    /// picture is clear there and another is under it; past each clear one to the first drawn
    /// there, else the one just under.
    static func topmost(_ targets: [AIMPSkinTarget], at point: CGPoint) -> AIMPSkinTarget? {
        let hits = targets.filter { $0.hit(point) }
        guard let top = hits.last else { return nil }
        guard top.isClear(at: point) else { return top }
        // Never to a scroll view's own area, which takes the wheel but no clicks: M5's switches
        // and dots are clear in their middles.
        let under = hits.dropLast().filter { !$0.isScrollArea }
        return under.last(where: { !$0.isClear(at: point) }) ?? under.last ?? top
    }

    /// A scroll view's whole area (its wheel), not its bar.
    var isScrollArea: Bool { if case .viewScroll(_, _, let thumb) = kind { thumb == 0 } else { false } }

    /// Whether its picture is clear at `point`, a hit on it (`pixels`).
    func isClear(at point: CGPoint) -> Bool {
        guard let pixels, pixels.width == Int(rect.width), pixels.height == Int(rect.height) else { return false }
        return !pixels.covers(Int(point.x - rect.minX), Int(point.y - rect.minY))
    }
}

/// The menus a skin's keys pop up (`PopupMenu`, a list's right-click) that NullPlayer has one like,
/// read once from AIMP's names; a name it has none for opens the player menu.
enum AIMPSkinPopup: Sendable, Equatable {
    /// The playlist's own (`pmPlaylistMain`, `pmMisc`), adding files (`pmAdd`), taking them out
    /// (`pmDelete`), sorting (`pmSorting`).
    case playlist, add, remove, sort
    /// The EQ presets.
    case equalizer
    /// The library window's own menu (`pmMLMisc`, `pmMLMainMenu`): adding to the library and
    /// rescanning it. Its tree's, table's, grouping presets' and removing menus have no stand-in:
    /// NullPlayer's library browser, over the lists, has its own.
    case library
    /// One the skin builds itself, by name (`AIMPSkinCustomMenu`): AIMP Modern's menu bar.
    case custom(String)
    /// Managing playlists (`pmManagePlaylist`): loading one, saving this one.
    case managePlaylist
    /// One of AIMP's own playlist and library menus NullPlayer has nothing like (quick options,
    /// jumping, the library table's views and grouping, the playlist list): its key is dimmed and
    /// opens nothing (`AIMPSkinLayout.unavailable`), not the player menu in its place (WMP12 SB's
    /// toolbar, where five keys opened that one menu).
    case unavailable

    static let unavailableNames: Set<String> = [
        "pmQuickOptions", "pmJump", "pmMLTable", "pmMLTableViews", "pmMLDelete", "pmMLGroupingPresets",
        "pmMLGroupingTree", "pmPlaylistList", "pmPlaylistTabs", "pmUtilities",
    ]

    init?(_ name: String) {
        if Self.unavailableNames.contains(name) { self = .unavailable; return }
        switch name {
        case "pmManagePlaylist": self = .managePlaylist
        case "pmPlaylistMain", "pmMisc": self = .playlist
        case "pmAdd": self = .add
        case "pmDelete": self = .remove
        case "pmSorting", "pmSort": self = .sort
        case "pmEqualizer", "pmEQPresets", "pmEQMenu", "pm_EQMenu": self = .equalizer
        case "pmMLMisc", "pmMLMainMenu": self = .library
        default: return nil
        }
    }
}

/// The lists a skin's windows draw from NullPlayer's: the playlist, and the library's table and
/// group tree. The raw value is the name a skin binds to (`Source="MLTable"`).
enum AIMPSkinList: String, Sendable {
    /// NullPlayer's one playlist's name on a skin's tabs and labels: AIMP's first playlist's, "Default".
    static let playlistName = "Default"

    case playlist = "Playlist"
    case libraryTable = "MLTable"
    case libraryTree = "MLGroupingTree"
}
