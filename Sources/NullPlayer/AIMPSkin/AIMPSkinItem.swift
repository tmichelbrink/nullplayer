import CoreGraphics
import Foundation

/// What items and controls share as the layout shows or hides them: a name scripts and bindings
/// find them by, their `Visibility` bindings, and whether the editor saved them shown.
protocol AIMPSkinElement: AnyObject {
    /// The node's `name`, as the skin wrote it (it may be empty).
    var name: String? { get }
    /// `Visibility` bindings: the element hides while any reads 0.
    var gates: [AIMPSkinLink] { get }
    /// Not saved hidden (`Visible`/`InitialVisible` False), or with `AutoHide`, which shows it
    /// whenever it fits whatever the editor saved (Soot's all-in-one trigger, saved hidden, shows
    /// once the window is 550 px wide).
    var savedShown: Bool { get }
}

/// A layout `item` of a form (or the form's root `layout`), read once as the skin loads
/// (`AIMPSkinIndex`): how it docks in its parent, its picture and colour, and the items and controls
/// it holds as the skin wrote them (a script may move some elsewhere: `AIMPSkinLayout.heldItems`).
final class AIMPSkinItem: AIMPSkinElement, Sendable {
    let name: String?
    let className: String?
    /// `Tag` and the `PlaceInfo` margins as the skin wrote them, which a script reads
    /// (`AIMPSkinIndex.Element`).
    let tag: String?
    let writtenMargins: [Double]
    let bindings: AIMPSkinBindings
    let gates: [AIMPSkinLink]
    let savedShown: Bool
    /// An `item`, not the form's root.
    let isItem: Bool
    let isTabbedGroup: Bool
    /// A `LayoutDockSite`, which holds a form of the skin's (`AIMPSkinDockSites`).
    let isDockSite: Bool
    /// A `LayoutScrollView`: what it holds is laid out at full height and scrolled through it (M5's
    /// skin settings, a 1,200-px page of options).
    let isScrollView: Bool
    let layout: Layout
    /// The `Texture` its picture fills it with, and the `Color` under it.
    let texture: String?
    let color: AIMPSkinColor?
    /// Whether it names a colour at all (an item showing nothing has none: `AIMPSkinLayout.isHollow`).
    let declaresColor: Bool
    let items: [AIMPSkinItem]
    let controls: [AIMPSkinControl]
    /// Whether the skin wrote its items before its controls: the first of a name is found in that
    /// order (`AIMPSkinIndex.byName`).
    let itemsFirst: Bool

    /// `isItem`: an `item`, not a form's root; `className` says whether it is a dock site, tabbed
    /// group or scroll view.
    init(name: String?, className: String?, isItem: Bool = true, layout: Layout, bindings: AIMPSkinBindings,
         texture: String? = nil, color: AIMPSkinColor? = nil, declaresColor: Bool = false,
         items: [AIMPSkinItem] = [], controls: [AIMPSkinControl] = [], itemsFirst: Bool = true,
         tag: String? = nil, writtenMargins: [Double] = []) {
        self.name = name
        self.className = className
        self.tag = tag
        self.writtenMargins = writtenMargins
        self.layout = layout
        self.bindings = bindings
        gates = bindings.all("Visibility")
        savedShown = layout.savedShown
        self.isItem = isItem
        isTabbedGroup = layout.isTabbedGroup
        isDockSite = className == "LayoutDockSite"
        isScrollView = className == "LayoutScrollView"
        self.texture = texture
        self.color = color
        self.declaresColor = declaresColor
        self.items = items
        self.controls = controls
        self.itemsFirst = itemsFirst
    }

    /// How an item docks in its parent (`reference/layout.md` § Items), as `AIMPSkinAlignment` reads it.
    struct Layout: Sendable {
        let isTabbedGroup: Bool
        /// `Alignment`, read once; nil where the item has none: it runs down from the top.
        let dock: AIMPSkinDock?
        /// `AlignmentLevel`: lower docks first, against its edge.
        let level: Int
        /// `AlignmentMargins` (l, t, r, b), which sit outside the item.
        let margins: AIMPSkinImage.Margins?
        /// `Size`, `SizeMinimal` and `SizeMaximal`, read once; nil unless two numbers are given.
        let size: CGSize?
        let sizeMinimal: CGSize?
        let sizeMaximal: CGSize?
        let autoHide: Bool
        /// `AutoHideParentSizeThreshold`, when one is given above 0.
        let autoHideThreshold: Double?
        /// `AutoSize` is not False: a docked item's size follows what it holds.
        let autoSize: Bool
        /// Its clients share it along its row: AIMP's default; `ldVertical` shares it down.
        let isRow: Bool
        /// Not saved hidden (`Visible` or `InitialVisible` False), or `AutoHide` (`AIMPSkinElement.savedShown`).
        let savedShown: Bool
        /// `AllowResizeByWidth` False: the user cannot widen or narrow it (Bento's 346-px basic view).
        let fixedWidth: Bool
        /// `AllowResizeByHeight` False: the user cannot make it taller or shorter (Arctur's top bar).
        let fixedHeight: Bool

        /// Whether its size follows what it holds; measuring the `least` a form takes, a client's
        /// still counts, its size being its parent's (Unsquareable's six cover sizes, one shown at a
        /// time, say `AutoSize` False).
        func sizesToContent(least: Bool = false) -> Bool { autoSize || (least && dock == .client) }

        /// `size` grown by its `AlignmentMargins`: the slot it takes.
        func slot(_ size: CGSize) -> CGSize {
            guard let m = margins else { return size }
            return CGSize(width: size.width + CGFloat(m.left + m.right), height: size.height + CGFloat(m.top + m.bottom))
        }

        /// `rect` inset by its `AlignmentMargins`.
        func inset(_ rect: CGRect) -> CGRect { margins?.inset(rect) ?? rect }

        /// `size` no smaller than its `SizeMinimal`, side by side.
        func floored(_ size: CGSize) -> CGSize {
            guard let minimal = sizeMinimal else { return size }
            return CGSize(width: max(size.width, minimal.width), height: max(size.height, minimal.height))
        }

        /// Along `vertical` or across, one of its sizes when it is given and above 0.
        static func extent(_ size: CGSize?, vertical: Bool) -> CGFloat? {
            guard let size else { return nil }
            let extent = vertical ? size.height : size.width
            return extent > 0 ? extent : nil
        }
    }
}

/// An item's `Alignment`: the edge it docks to, or the room the docked ones leave (`laClient`). Any
/// other value (`laNone`) docks it nowhere: it lies over the room left, where an item with no
/// `Alignment` at all runs down from the top.
enum AIMPSkinDock: Hashable, Sendable {
    case top, bottom, left, right, client, none

    init(_ value: String?) {
        switch value {
        case "laTop": self = .top
        case "laBottom": self = .bottom
        case "laLeft": self = .left
        case "laRight": self = .right
        case "laClient": self = .client
        default: self = .none
        }
    }

    /// A side panel's: docked across its parent.
    var isSide: Bool { self == .left || self == .right }
}

extension AIMPSkinImage.Margins {
    /// Four numbers, left, top, right, bottom (`AlignmentMargins` "0,4,0,4"); nil for anything else.
    init?(_ text: String?) {
        let m = AIMPNode.numbers(text)
        guard m.count == 4 else { return nil }
        self.init(left: m[0], top: m[1], right: m[2], bottom: m[3])
    }
}

/// A colour property, read one way wherever a skin gives one: an ARGB number of its own, as its
/// `value` (LX-tix's `-16777216`, black) or a nested `Value` (Unsquareable's items, the list styles),
/// else the resource its `ID` names, which a script may repoint (`AIMPSkin.color(_:links:)`).
/// `.acs3` writes Delphi colours instead (`delphi`).
enum AIMPSkinColor: Sendable, Equatable {
    case argb(UInt32)
    case resource(String)

    init?(_ property: AIMPNode?) {
        guard let property else { return nil }
        if let argb = Self.number(property) {
            self = .argb(UInt32(truncatingIfNeeded: argb))
        } else if let name = property.reference {
            self = .resource(name)
        } else {
            return nil
        }
    }

    /// The property's own ARGB, nil for none or a clear one: what a list's rows and an equalizer
    /// display's lines are drawn in, where a clear colour draws nothing.
    static func visible(_ property: AIMPNode?) -> UInt32? {
        guard case .argb(let argb)? = AIMPSkinColor(property), argb >> 24 != 0 else { return nil }
        return argb
    }

    /// `.acs3`'s colour, a Delphi number as the property's `value` (`ColorContent`, the playlist's
    /// `ItemHighlightColorPlaying`), as ARGB.
    static func delphi(_ property: AIMPNode?) -> UInt32? {
        property?["value"].flatMap { Int64($0) }.map(argb(delphi:))
    }

    /// The number a property holds: its `value`, else a nested `Value`'s.
    private static func number(_ property: AIMPNode) -> Int64? {
        (property["value"] ?? property.named["Value"]?["value"]).flatMap { Int64($0) }
    }
}

extension AIMPSkinItem {
    /// The first item called `name` in this one, itself included, depth first.
    func item(named name: String) -> AIMPSkinItem? {
        if isItem, self.name == name { return self }
        return items.lazy.compactMap { $0.item(named: name) }.first
    }
}
