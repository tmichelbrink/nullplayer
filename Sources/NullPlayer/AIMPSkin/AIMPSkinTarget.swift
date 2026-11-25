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

/// What a click, or a wheel notch, does to a skin counter's position or a tabbed group's page: the
/// skin's `Expression` over the current one (`Value`), compiled once and sorted by what the wheel
/// does with it.
struct AIMPSkinStep: Equatable, Sendable {
    /// Nil for none, or one that does not parse: a click leaves the position where it is.
    let expression: AIMPSkinExpression?
    let wheel: Wheel

    enum Wheel: Equatable, Sendable {
        /// Takes no notches: the expression picks a position, or there is none.
        case none
        /// One position a notch, stopping at the ends; a click steps to the next, however the skin
        /// spells it (`Value + 1`, `(value+1)mod 3`, `(Value + 1) MOD 6`). Akai CS-F33's TAPE
        /// SELECTOR, Pioneer's TAPE switch.
        case next
        /// The notches are the expression's `ScrollDelta` (`Value + ScrollDelta`: Denon DR-F8's
        /// MONITOR); a click is one.
        case scrollDelta
    }

    init(_ text: String?) {
        expression = text.flatMap(AIMPSkinExpression.init)
        if expression?.reads("scrolldelta") == true {
            wheel = .scrollDelta
        } else if expression?.stepsToNext == true {
            wheel = .next
        } else {
            wheel = .none
        }
    }

    /// The fixed position the expression names (`3`): what a right-click's `ContextMenu` sets.
    var position: Int? { expression?.constant.flatMap { Int(exactly: $0) } }

    /// Where a click, or `notches` of the wheel, takes `current`; nil where the expression gives
    /// nothing (none, one that does not evaluate, or a number no `Int` position holds), and the
    /// position stays.
    func next(from current: Double, notches: Int = 1) -> Double? {
        var variables = ["value": current]
        if wheel == .scrollDelta { variables["scrolldelta"] = Double(notches) }
        guard let next = expression?.evaluate(variables: variables), Int(exactly: next.rounded(.towardZero)) != nil else { return nil }
        return next
    }
}

/// A picture's pixels, read once as the frame is drawn (off main), so a hit test on main reads one
/// byte of them rather than copying the picture.
struct AIMPAlphaMask: Equatable, Sendable {
    let width: Int
    let height: Int
    private let pixels: Data
    private let bytesPerRow: Int
    /// Where alpha sits in a pixel: first of ARGB or last of RGBA, in memory order.
    private let offset: Int

    /// Nil for a picture that is not 32 bits a pixel (hit as its whole rect).
    init?(_ image: CGImage?) {
        guard let image, image.bitsPerPixel == 32, let data = image.dataProvider?.data else { return nil }
        // Alpha is the first byte of ARGB, or the last; little-endian swaps the order in memory.
        let alphaFirst = [CGImageAlphaInfo.premultipliedFirst, .first].contains(image.alphaInfo)
        offset = alphaFirst != image.bitmapInfo.contains(.byteOrder32Little) ? 0 : 3
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        pixels = data as Data
    }

    func covers(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let at = y * bytesPerRow + x * 4 + offset
        return at < pixels.count && pixels[pixels.startIndex + at] > 0
    }

    /// The bounding box of every pixel with any alpha, nil when nothing is drawn: the part of a
    /// frame a window shows (`AIMPSkinMainView.contentRect`). Measured inward from the edges, so a
    /// solid deck costs a row and a column rather than every pixel: it runs whenever a counter or
    /// page changes, which some skins do every tick (Sony TC-RX80's reels).
    var drawnBounds: CGRect? {
        pixels.withUnsafeBytes { raw -> CGRect? in
            let bytes = raw.bindMemory(to: UInt8.self)
            func drawn(_ x: Int, _ y: Int) -> Bool {
                let at = y * bytesPerRow + x * 4 + offset
                return at < bytes.count && bytes[at] > 0
            }
            func rowDrawn(_ y: Int) -> Bool { (0..<width).contains { drawn($0, y) } }
            guard let minY = (0..<height).first(where: rowDrawn),
                  let maxY = (minY..<height).reversed().first(where: rowDrawn) else { return nil }
            var minX = width, maxX = -1
            for y in minY...maxY {
                // Only the columns outside what is already known can widen the box.
                if let x = (0..<minX).first(where: { drawn($0, y) }) { minX = x }
                if let x = (max(maxX + 1, minX)..<width).reversed().first(where: { drawn($0, y) }) { maxX = x }
            }
            guard maxX >= minX else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }
}

/// One drawn frame and what can be clicked on it.
struct AIMPSkinFrame: Sendable {
    let image: CGImage
    /// Topmost last, as drawn.
    let targets: [AIMPSkinTarget]
    /// The image's alpha: where the window is.
    var alpha: AIMPAlphaMask?
    /// Each shown control's tooltip (its `Hint`), topmost last.
    var hints: [(rect: CGRect, text: String)] = []
    /// Where each named item and control was drawn, for `IsActive` on the next frame.
    var namedRects: [String: CGRect] = [:]
    /// A control's `OnMouseEnter`, `OnMouseMove` and `OnMouseLeave` handlers, where it was drawn.
    struct MouseHandlers: Sendable {
        let name: String
        let rect: CGRect
        let enter: String?
        let move: String?
        let leave: String?
    }
    var mouseHandlers: [MouseHandlers] = []
    /// Each gauge's value this frame and how fast it may rise and fall toward it, in its units
    /// per thirtieth of a second.
    var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
    /// The quick search box's font, for the field the window types into over it.
    var searchFont: AIMPSkinFont?
    /// The items this layout hid (`AIMPSkinState.Script.autoHidden`), for the next frame's bindings.
    var autoHidden: Set<String> = []
    /// Pixels of `image` per skin pixel (the window's UI size times the screen's); every rect and
    /// point here is in skin pixels.
    var scale: CGFloat = 1

    func target(at point: CGPoint) -> AIMPSkinTarget? { AIMPSkinTarget.topmost(targets, at: point) }
    func hint(at point: CGPoint) -> String? { hints.last { $0.rect.contains(point) }?.text }

    /// Whether a pixel is part of the window: anything drawn there.
    func isOpaque(at point: CGPoint) -> Bool { alpha?.covers(Int(point.x * scale), Int(point.y * scale)) ?? false }

    /// What the frame draws, in skin pixels (`AIMPAlphaMask.drawnBounds`, which counts `image`'s).
    var drawnBounds: CGRect? {
        alpha?.drawnBounds.map {
            CGRect(x: ($0.minX / scale).rounded(.down), y: ($0.minY / scale).rounded(.down),
                   width: ($0.maxX / scale).rounded(.up) - ($0.minX / scale).rounded(.down),
                   height: ($0.maxY / scale).rounded(.up) - ($0.minY / scale).rounded(.down))
        }
    }

    /// `rect`, in skin pixels, as a rect of `image`.
    func imageRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
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
