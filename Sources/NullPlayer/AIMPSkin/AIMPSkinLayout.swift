import CoreGraphics
import Foundation

/// A frame laid out, before anything is drawn: every shown item placed by AIMP's docking rules
/// (`reference/layout.md` § Items, `AIMPSkinAlignment`), and in each the controls it shows, placed, with
/// what a key shows and what the pointer can do to it. The painter draws the tree
/// (`AIMPSkinPainter.paint`); the frame's click targets, tooltips, named rects and handlers are read
/// from it (`Tree.offers`), and a window's natural size from it alone.
final class AIMPSkinLayout {
    /// What an unsupported key's tooltip says (`Control.unavailable`), and a skin menu's item.
    static let unavailableNote = "Not available in NullPlayer"
    /// An item placed, the controls it shows in drawing order, and the items it holds.
    struct Item {
        let item: AIMPSkinItem
        let rect: CGRect
        var controls: [Control]
        var items: [Item]
        /// A scroll view's own rect, which `rect`, its whole content, scrolls through, and how far.
        var visible: CGRect? = nil
        var maxTop: CGFloat = 0
    }

    /// A control placed: where `PlaceInfo` puts it, where it draws (a display grown to its text),
    /// how it looks and what it offers the pointer, and the controls placed in it.
    struct Control {
        /// As a script restyled it.
        let control: AIMPSkinControl
        let image: AIMPSkinImage?
        let placed: CGRect
        let rect: CGRect
        /// The item's rect its window cuts it at (W10's cover strip).
        let cut: CGRect?
        var look: Look
        /// Its click targets, topmost last, and its tooltip.
        var targets: [AIMPSkinTarget]
        let hint: String?
        /// A key wired to what NullPlayer does not do: dimmed, and its tooltip says so.
        var unavailable = false
        /// A gauge the window eases: its value and how fast it may rise and fall.
        /// What the window eases from frame to frame, by the id it is eased under: a gauge's needle,
        /// the VU meters' two needles (`AIMPSkinControl.ID.meter`).
        let gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)]
        var controls: [Control]
    }

    /// How a control looks this frame, all the painter needs to draw it: its class's settings and
    /// what the frame's state makes of them. The painter switches on it once.
    enum Look {
        /// A key, or a control drawn as one: this frame of its picture, a panel's fill, its caption
        /// (`glyphFirst`: its centred glyph at its left, before the spaces the caption opens with).
        case key(AIMPControlClass.Key, frame: Int, caption: String, glyphFirst: Bool)
        /// Its picture, as it is (a library list with no library to list).
        case picture
        /// One frame of its filmstrip: a gauge's needle, an animator's step, a selector's position,
        /// a state display's state, a digit key held down.
        case frame(Int)
        case digits(value: Double, AIMPControlClass.Digits)
        case time(seconds: Int, AIMPControlClass.Digits)
        /// A slider's or seek bar's value, 0–1, and its thumb.
        case slider(AIMPControlClass.Slider, fraction: Double, thumb: AIMPSkinImage?)
        case rating(Int)
        /// NullPlayer's playlist, the rows the quick search leaves (`shown`), and those in view.
        case playlist(AIMPSkinControl.Playlist, rows: Rows, shown: [Int])
        /// The library's tree or table: only the list's fill, which NullPlayer's library browser
        /// covers in the window (`AIMPSkinTarget.Kind.libraryArea`).
        case libraryArea(fill: UInt32?)
        /// The playlist's scroll bar: its thumb, `length` long, `share` of the way down (nil: all
        /// the rows are in view).
        case scrollBar(thumb: AIMPSkinImage?, length: CGFloat, share: CGFloat?)
        /// A quick search box and the search shown in it, if any.
        case search(String?, font: AIMPSkinFont)
        case tabControl(AIMPSkinControl.Tabs, caption: String)
        case playlistTabs(AIMPSkinControl.Tabs, playing: Bool)
        case playlistBox(font: AIMPSkinFont?, centred: Bool)
        case equalizer(preamp: UInt32?, curve: UInt32?)
        case coverArt(AIMPControlClass.Cover)
        case glass(blur: Double?, tint: AIMPSkinColor?)
        /// The track's waveform, `played` (0–1) of it lit, in ARGB colours.
        case waveform(peaks: [UInt16], played: Double, background: UInt32?, content: UInt32?, rest: UInt32? = nil, thumb: AIMPSkinImage? = nil)
        case waveForm(AIMPControlClass.Trace)
        case visualization(AIMPControlClass.Spectrum, cover: Int?)
        case spectrum(AIMPControlClass.Spectrum)
    }

    /// The rows of the playlist in view: from row `first` (of those the quick search leaves), each a
    /// slot down from the list's top, a group's header band above the track that starts it.
    /// `visible` are the rows wholly in view, as scrolling and the scroll bar count them.
    struct Rows: Equatable, Sendable {
        struct Slot: Equatable, Sendable {
            /// The row, a position in the rows the quick search leaves.
            let row: Int
            /// Down from the list's top; the header band's height (0 with none) and the whole slot's.
            let top: CGFloat
            let header: CGFloat
            let height: CGFloat
        }

        let first: Int
        let visible: Int
        let slots: [Slot]
        /// The playlist and quick search they were laid out for: a click is resolved only against the
        /// rows it saw drawn (`AIMPSkinPlayerSnapshot.Playlist.generation`).
        var generation = 0
        var search = ""

        /// `count` rows, each `height(row)` tall with its header, in `room`, from row `top`, or as
        /// near it as lets the last row show at the bottom.
        init(top: Int, count: Int, room: CGFloat, height: (Int) -> (header: CGFloat, item: CGFloat)) {
            var lastFirst = count, used: CGFloat = 0
            while lastFirst > 0 {
                let next = height(lastFirst - 1)
                guard used + next.header + next.item <= room else { break }
                used += next.header + next.item
                lastFirst -= 1
            }
            first = min(max(0, top), max(0, min(lastFirst, count - 1)))
            var slots: [Slot] = [], y: CGFloat = 0, whole = 0, row = first
            while row < count, y < room {
                let size = height(row)
                slots.append(Slot(row: row, top: y, header: size.header, height: size.header + size.item))
                y += size.header + size.item
                if y <= room { whole += 1 }
                row += 1
            }
            self.slots = slots
            visible = max(1, whole)
        }

        /// The row whose track is at `y` down from the list's top; nil over a header or below the rows.
        func row(at y: CGFloat) -> Int? {
            slots.first { y >= $0.top + $0.header && y < $0.top + $0.height }?.row
        }
    }

    let flow: AIMPSkinDataflow
    let interaction: AIMPSkinInteraction
    var skin: AIMPSkin { flow.skin }
    /// AIMP 3.0's and AIMP 2's controls belong to the window, not to their item (`controls(of:)`).
    let controlsOutliveItems: Bool
    /// Items this layout hid by their `AutoHide` (`autoHides`).
    private(set) var autoHidden: Set<String> = []
    /// Each scroll view laid out, by name: how far it is scrolled, how far it can be, how much of
    /// it is in sight and how tall its content is (`withScrollBars` sizes its bar by it).
    private(set) var scrolls: [String: Scroll] = [:]

    struct Scroll {
        let top: CGFloat
        let maxTop: CGFloat
        let visible: CGFloat
        let content: CGFloat
    }
    /// What this frame measured, by item and what was asked: each subtree is measured once however
    /// often docking asks (an item's slot, its `AutoHide` test and a pulled item's height all ask for
    /// its size; a row's clients for what they hold and whether they are hollow). Frame sizes are
    /// kept by depth too, as the measure stops at a depth (`size`).
    private var sizes: [Measured: CGSize] = [:]
    private var hollow: [ObjectIdentifier: Bool] = [:]
    private struct Measured: Hashable {
        let item: ObjectIdentifier
        let measure: Measure
    }

    /// Which size of an item is asked for (`measured`): as this frame shows it, `depth` levels down
    /// the measure (`size`); or the least it takes as the skin was saved, `page` as a tabbed group's
    /// page (`leastSize`).
    enum Measure: Hashable {
        case frame(depth: Int)
        case least(page: Bool)
    }

    /// Least sizes take every page of a tabbed group, not the one it shows (`leastSize`): for a
    /// window whose shown pages measure nothing before its scripts run (IpplePlay's).
    var leastByEveryPage = false

    init(flow: AIMPSkinDataflow, interaction: AIMPSkinInteraction = .init()) {
        self.flow = flow
        self.interaction = interaction
        controlsOutliveItems = flow.skin.archive.isLegacy
    }

    /// A form, or its item `rootName`, laid out at `size`; nil for a form or item the skin lacks.
    func tree(size: CGSize, item rootName: String? = nil, form formName: String? = nil) -> Tree? {
        guard let form = skin.index.form(formName) else { return nil }
        let root: AIMPSkinItem
        if let rootName {
            guard let item = form.item(named: rootName) else { return nil }
            root = item
        } else {
            root = form
        }
        return Tree(root: withScrollBars(tree(root, in: CGRect(origin: .zero, size: size))), rootIsItem: rootName != nil,
                    autoHidden: autoHidden)
    }

    /// `item` placed at `rect`, its controls, then the items it holds, placed in turn: the order the
    /// painter draws them in.
    func tree(_ item: AIMPSkinItem, in rect: CGRect) -> Item {
        if item.isScrollView, let name = item.name { return scrolledTree(item, named: name, in: rect) }
        let children = layout(item, in: rect)
        let controls = self.controls(of: item, in: rect)
        return Item(item: item, rect: rect, controls: controls, items: children.map { tree($0.0, in: $0.1) })
    }

    /// A scroll view: what it holds laid out at its full height, moved up by how far it is
    /// scrolled; the painter clips it to `rect`, and what it scrolled out of sight takes no clicks.
    private func scrolledTree(_ item: AIMPSkinItem, named name: String, in rect: CGRect) -> Item {
        let content = AIMPSkinAlignment.content(item, children: shownItems(of: item)) { measured($0, .frame(depth: 0)) }
        let height = max(rect.height, content.height), maxTop = height - rect.height
        let top = min(max(0, CGFloat(flow.state.script[name].scrollTop ?? 0)), maxTop).rounded()
        scrolls[name] = Scroll(top: top, maxTop: maxTop, visible: rect.height, content: height)
        let page = CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: height)
        var placed = Item(item: item, rect: page, controls: controls(of: item, in: page),
                          items: layout(item, in: page).map { tree($0.0, in: $0.1) })
        placed.visible = rect
        placed.maxTop = maxTop
        return placed
    }

    // MARK: Items

    /// The items of `item` that show: a tabbed group's active page, else every shown child. A dock
    /// site shows while it holds its form, docked and shown (Telos's equalizer starts hidden, over
    /// its transport panel); one holding none takes no room (A4 3.2's library site, its library a
    /// window, leaves the split view to the playlist).
    func shownItems(of item: AIMPSkinItem) -> [AIMPSkinItem] {
        AIMPSkinAlignment.participants(heldItems(item), of: item, pages: .active { self.flow.activePage($0) }, index: skin.index) { item in
            guard item.isDockSite else { return flow.isShown(item) }
            guard let form = item.name.flatMap({ skin.index.sites[$0]?.form }) else { return false }
            return flow.isDocked(form) && flow.isVisible(form) && flow.isShown(item)
        }
    }

    /// Whether `item`, when it is a dock site, holds its form docked and shown, as `shownItems` lays
    /// it out: an empty site takes no room in the window's least size either. Lumin's split view holds
    /// a 603-px library site beside its 425-px playlist site; AIMP 5.40 opens the 443-px player over
    /// its playlist, the library a window of its own, where counting both opened it 1,046 px wide.
    private func siteHolds(_ item: AIMPSkinItem) -> Bool {
        guard item.isDockSite else { return true }
        guard let form = item.name.flatMap({ skin.index.sites[$0]?.form }) else { return false }
        return flow.isDocked(form) && flow.isVisible(form)
    }

    /// What `item` holds now: its own items, less any a script moved out, plus any it moved in
    /// (`Parent :=`); a dock site also holds its form while it is docked.
    func heldItems(_ item: AIMPSkinItem) -> [AIMPSkinItem] {
        var held = moved(item.items, holder: item.name) { if case .item(let item) = $0 { item } else { nil } }
        if let name = item.name, let site = skin.index.sites[name], flow.isDocked(site.form), let holder = skin.index.holders[name] {
            held.append(holder)
        }
        return held
    }

    /// The controls an item or control holds now (`own`), as `heldItems`.
    func heldControls(_ element: AIMPSkinElement, own: [AIMPSkinControl]) -> [AIMPSkinControl] {
        moved(own, holder: element.name) { if case .control(let control) = $0 { control } else { nil } }
    }

    /// `own` less any a script moved out of `holder`, plus any it moved in, by name.
    private func moved<Element: AIMPSkinElement>(_ own: [Element], holder name: String?,
                                                 as kind: (AIMPSkinIndex.Element) -> Element?) -> [Element] {
        let moved = flow.state.script.parents
        guard !moved.isEmpty else { return own }
        // An unnamed holder (a form's root) keeps none it lost either, so an item moved under its own
        // descendant is not reached twice, round and round.
        let kept = own.filter { child in child.name.flatMap { moved[$0] }.map { $0 == name } ?? true }
        guard let name else { return kept }
        return kept + moved.filter { $0.value == name && skin.index.parentOf[$0.key] != name }.keys.sorted()
            .compactMap { skin.index.byName[$0].flatMap(kind) }
    }

    /// Where `item`'s shown items go in `rect`: docked edges first, by level; items with no
    /// `Alignment` down from the top; clients sharing what is left; each inset by its margins.
    func layout(_ item: AIMPSkinItem, in rect: CGRect) -> [(AIMPSkinItem, CGRect)] {
        var items = shownItems(of: item)
        // A tab page with no size of its own fills its group, whatever its alignment: pages are
        // alternatives, not a stack (Kantaris-Teyp's deck pages say none, and stood 49 px tall in a
        // 250-px group). One with a picture keeps its size (Nakamichi BX's slider scales).
        if item.isTabbedGroup, items.count == 1, let page = items.first, !hasOwnSize(page) {
            return [(page, page.layout.inset(rect))]
        }
        // Clients share along the row unless the item says `ldVertical`: AIMP's default, so a
        // caption's icon, title and keys need no direction.
        let horizontal = item.layout.isRow
        items = items.filter { item in
            guard autoHides(item, in: rect, row: horizontal) else { return true }
            if let name = item.name { autoHidden.insert(name) }
            return false
        }
        var free = rect
        var placed: [Int: CGRect] = [:]
        // An item's `AlignmentMargins` sit outside it: its slot is its size plus them (Sony TC-MR2's
        // cassette docks left with 85 px before it and 509 after), and it is inset from the slot below.
        func slot(_ item: AIMPSkinItem) -> (CGFloat, CGFloat) {
            let slot = item.layout.slot(size(item))
            return (slot.width, slot.height)
        }
        let order = AIMPSkinAlignment.levelOrder(items.map(\.layout))
        for i in order {
            let (w, h) = slot(items[i])
            switch items[i].layout.dock {
            case .top?:
                placed[i] = CGRect(x: free.minX, y: free.minY, width: free.width, height: h)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
            case .bottom?:
                placed[i] = CGRect(x: free.minX, y: free.maxY - h, width: free.width, height: h)
                free.size.height -= h
            case .left?:
                placed[i] = CGRect(x: free.minX, y: free.minY, width: w, height: free.height)
                free = CGRect(x: free.minX + w, y: free.minY, width: free.width - w, height: free.height)
            case .right?:
                placed[i] = CGRect(x: free.maxX - w, y: free.minY, width: w, height: free.height)
                free.size.width -= w
            default:
                break
            }
        }
        // Where negative margins pull an item back over the run (TEAC CD-RW890's NEXT key: 20 px tall
        // with -20 above, beside PREV, 20 tall with -84 above), its slot is 0 or less: it sits at its
        // margins and the run moves on by the slot.
        // Items with no `Alignment` run down from the top in `AlignmentLevel` order whatever the
        // parent's `LayoutDirection` (Soot's 50-px caption bar over its three transport keys, laid
        // side by side); one with no height of its own takes what remains.
        var pulled: [Int: CGRect] = [:]
        for i in order where placed[i] == nil && items[i].layout.dock == nil {
            let item = items[i]
            var (_, h) = slot(item)
            let ih = size(item).height
            // Once a page down it has been turned, at least as tall as what it then holds needs:
            // Kantaris-Teyp's 37-px `Ana2` holds its cassette page, and the track-info and wave
            // bars its settings show under it; at 37 px those piled up over the cassette.
            if h > 0, ih > 0, holdsTurnedPage(item) {
                let least = leastSize(item).height
                if least > ih { h += least - ih }
            }
            if let m = item.layout.margins, h <= 0 && ih > 0 {
                pulled[i] = CGRect(x: free.minX + CGFloat(m.left), y: free.minY + CGFloat(m.top), width: free.width - CGFloat(m.left + m.right), height: ih)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
                continue
            }
            if h > 0 {
                placed[i] = CGRect(x: free.minX, y: free.minY, width: free.width, height: h)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
            }
        }
        var clients = items.indices.filter { placed[$0] == nil && pulled[$0] == nil && items[$0].layout.dock == .client }
        // A client with nothing to show takes no share of the row beside one that has (RealPlayer
        // 11's empty `EqualizerFrame` held 300 px of its info strip open on the desktop).
        if clients.count > 1, clients.contains(where: { !isHollow(items[$0]) }) {
            for i in clients where isHollow(items[i]) {
                placed[i] = horizontal ? CGRect(x: free.minX, y: free.minY, width: 0, height: free.height)
                    : CGRect(x: free.minX, y: free.minY, width: free.width, height: 0)
            }
            clients.removeAll { placed[$0] != nil }
        }
        if clients.count > 1 {
            // Each at least what it holds needs (LX-tix's cover beside its 200-px info panel).
            let least = clients.map { leastSize(items[$0]) }
            let shares = AIMPSkinAlignment.share(free, among: clients.map { items[$0].layout }, vertical: !horizontal,
                                            minimums: least.map { horizontal ? $0.width : $0.height })
            for (i, rect) in zip(clients, shares) { placed[i] = rect }
        }
        return items.enumerated().map { i, item in
            (item, pulled[i] ?? item.layout.inset(placed[i] ?? free))
        }
    }

    /// Whether a panel in `item`'s tree has been turned on: a tabbed group with an empty "off" page,
    /// turned (by a key or a script) to a page with content (Kantaris-Teyp's track-info and wave
    /// bars). A group turned between two full pages is not (WMP12 SB's two toolbar rows).
    private func holdsTurnedPage(_ item: AIMPSkinItem) -> Bool {
        if item.isTabbedGroup, let name = item.name, let active = flow.state.script[name].activePage {
            func empty(_ page: AIMPSkinItem) -> Bool { page.items.isEmpty && page.controls.isEmpty }
            let pages = item.items.filter { $0.name.flatMap { skin.index.tabOf[$0] } != nil }
            let shown = pages.first { $0.name.flatMap { skin.index.tabOf[$0]?.index } == active }
            if let shown, !empty(shown), pages.contains(where: empty) { return true }
        }
        return item.items.contains { holdsTurnedPage($0) }
    }

    /// An item's declared size; a side it leaves at 0 takes its texture's (AIMP sizes such an item to
    /// its picture: Technicss docks a 0×0 `Deck` whose texture is the whole player), else its shown
    /// children's docked (Nakamichi BX docks a pictureless `Deck` around its 306-px face). Measured
    /// once a frame (`sizes`).
    func size(_ item: AIMPSkinItem, depth: Int = 0) -> CGSize { measured(item, .frame(depth: depth)) }

    /// What an item's `SizeMinimal`s add up to as AIMP docks them (`AIMPSkinAlignment.content`), each
    /// with its `AlignmentMargins`; a tabbed group's saved-shown pages are alternatives. An item that
    /// declares none and holds none counts its picture when it is a tabbed group's page and the
    /// picture a real one (`AIMPSkinPolicy.pictureSide`: RealPlayer 11's 210-px cover page): a page is
    /// sized by what it shows. It reads the skin as written, not the frame's state: a row's clients
    /// take at least this (LX-tix's cover beside its info panel), and a window opens no smaller.
    func leastSize(_ item: AIMPSkinItem, page: Bool = false) -> CGSize { measured(item, .least(page: page)) }

    /// `item`'s size as `measure` asks, measured once a frame.
    private func measured(_ item: AIMPSkinItem, _ measure: Measure) -> CGSize {
        let key = Measured(item: ObjectIdentifier(item), measure: measure)
        if let size = sizes[key] { return size }
        var size = self.measure(item, measure)
        // A scroll view's window need not hold all it scrolls (`scrolledTree` measures that itself).
        if item.isScrollView { size.height = min(size.height, AIMPSkinPolicy.scrollViewRoom) }
        sizes[key] = size
        return size
    }

    /// The one sizing rule both measures follow, each with its own children and pictures: what the
    /// item holds docked (`AIMPSkinAlignment.content`: every child in its slot, as `layout` places it),
    /// no smaller than its `SizeMinimal`.
    private func measure(_ item: AIMPSkinItem, _ measure: Measure) -> CGSize {
        let layout = item.layout
        switch measure {
        case .least(let pageItem):
            let holds = layout.sizesToContent(least: true)
            let tabbed = item.isTabbedGroup
            let shown = AIMPSkinAlignment.participants(item.items, of: item, pages: .everyElseFirst, index: skin.index) {
                holds && $0.savedShown && !self.hiddenWithPage($0) && !self.hiddenBySkinState($0) && self.siteHolds($0)
            }
            // A tabbed group showing an empty page, an "off" page beside a panel, takes no room, as
            // AIMP sizes the window to what it shows: Kantaris-Teyp's track-info and wave-bar panels
            // are such pages (`ParcaBilgino`, `SeekBarno`); their 178-px panel opened the window that
            // much taller, a see-through gap over its transport bar. A group showing a page with
            // content is as big as its biggest page (Easiness 2's and BLACK ONIX's views), as is one
            // whose shown page is so only by state not yet run, or under `leastByEveryPage`.
            let active = tabbed && !leastByEveryPage ? item.name.map { flow.activePage($0) } : nil
            let page = active.flatMap { active in shown.first { $0.name.flatMap { skin.index.tabOf[$0]?.index } == active } }
            // Once turned (by a key or a script), the page shown alone: Kantaris-Teyp's mini player
            // page gives back the cassette's height, its info panel takes its own.
            let turned = item.name.map { flow.state.script[$0].activePage != nil } ?? false
            // An empty page is "off" only beside a page with content (Prolux Revolution's one page,
            // `G1`, holds nothing but its picture, which sizes it).
            let off = { (page: AIMPSkinItem) in page.items.isEmpty && page.controls.isEmpty && shown.count > 1 }
            let children = page.map { off($0) ? [] : turned ? [$0] : shown } ?? shown
            var size = layout.floored(AIMPSkinAlignment.content(item, children: children) { measured($0, .least(page: tabbed)) })
            // One the user cannot size by height keeps the height its pictures give it: Arctur's top
            // bar (`Main`, its 61-px picture on the bar inside it) over its playlist site's 220-px
            // minimum, which AIMP 5.40 opens at 281; Protoss's whole 644-px face.
            if layout.fixedHeight, item.isItem {
                size.height = max(size.height, measured(item, .frame(depth: 0)).height)
            }
            if pageItem, layout.sizeMinimal == nil, size == .zero, item.isItem, let picture = skin.image(item.texture), AIMPSkinPolicy.isPicture(picture) {
                return picture.frameSize
            }
            return size
        case .frame(let depth):
            var size = layout.floored(layout.size ?? .zero)
            if size.width == 0 || size.height == 0, let picture = flow.image(item.texture), picture.hasPixels {
                if size.width == 0 { size.width = picture.frameSize.width }
                if size.height == 0 { size.height = picture.frameSize.height }
            }
            // `SizeMinimal` is only a minimum: the item grows to hold its children, their margins included
            // (RealPlayer 11's 60-px `Conta` holds a 210-px cover 17 px down, above the equalizer).
            let grows = layout.size == nil && layout.sizeMinimal != nil
            // `AutoSize` `False` keeps a size the item has; one with none at all still holds its children
            // (Unsquareable's cover column, 0 px wide, let its 192-px cover lie under the title). Eight
            // levels down the measure stops: a script may have moved an item into its own child.
            guard size.width == 0 || size.height == 0 || grows, depth < 8, layout.sizesToContent() || size == .zero else { return size }
            // Children as `layout` places them (FLAT DARK's 48-px top: a 24-px caption over a 24-px
            // menu); of a tabbed group, the page it shows (Bento's 155-px basic view, not its 161-px
            // advanced ones, whose height would stretch the basic one's picture).
            let shown = AIMPSkinAlignment.participants(heldItems(item), of: item, pages: .active { self.flow.activePage($0) },
                                                       index: skin.index, isShown: flow.isShown)
            let content = AIMPSkinAlignment.content(item, children: shown) { measured($0, .frame(depth: depth + 1)) }
            if size.width == 0 { size.width = content.width } else if grows { size.width = max(size.width, content.width) }
            if size.height == 0 { size.height = content.height } else if grows { size.height = max(size.height, content.height) }
            return size
        }
    }

    /// Whether `item` shows only with a tabbed group's page that group is not on: Bento's tab
    /// strips, one per view (`La`, `La2`, `La3`), side by side in one row, each the room of its own.
    private func hiddenWithPage(_ item: AIMPSkinItem) -> Bool {
        item.gates.contains { gate in
            guard gate.pin == "Visibility", let page = gate.source, skin.index.tabOf[page] != nil else { return false }
            return !flow.isOnActivePage(page)
        }
    }

    /// Whether `item` is hidden by the skin's own state at its start: a `Visibility` binding that reads
    /// 0 from what only the skin moves (`isSkinState`). Lux & Nox's player (`master`, shown at
    /// position 2 of the counter `skinWelcomeScreenProvider`) sits under its 550-px welcome screen,
    /// shown at 0 and 1: AIMP 5.40 opens the 870×550 welcome screen alone, and counting both opened
    /// an 870×1100 window, its bottom half empty. Messa's dock area (`mwDockSites`) shows while its
    /// playlist site does, through a commutator; AIMP opens the 562×247 player alone. Bindings to the
    /// player (its state, the track) are not read here: they change as it plays, and the window is
    /// sized for them. Nor are an `.acs3` skin's, made by NullPlayer's translation, not by the skin.
    private func hiddenBySkinState(_ item: AIMPSkinItem) -> Bool {
        guard skin.archive.format != .acs3 else { return false }
        return item.gates.contains { gate in
            guard let source = gate.source, isSkinState(source, pin: gate.pin) else { return false }
            return flow.value(of: gate) == 0
        }
    }

    /// Whether `source`'s `pin` moves only with the skin's own state: a counter, scripted or not (both
    /// start at their default position in AIMP: M5's scripted panels open its 752×511 window, which
    /// counting them shown opened at 1001×772), an item's or control's `Visibility`, or a commutator
    /// over such values.
    private func isSkinState(_ source: String, pin: String?, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        if skin.index.byName[source] != nil { return pin == "Visibility" }
        guard let provider = skin.index.providers[source] else { return false }
        switch provider.kind {
        case .counter: return true
        case .commutator:
            let links = provider.bindings.links
            return !links.isEmpty && links.allSatisfy { link in
                link.source.map { isSkinState($0, pin: link.pin, depth: depth + 1) } ?? false
            }
        default: return false
        }
    }

    /// Whether an item shows nothing: no size, picture or colour of its own, no controls, and only
    /// items like it inside.
    func isHollow(_ item: AIMPSkinItem) -> Bool {
        if let known = hollow[ObjectIdentifier(item)] { return known }
        let isHollow = !hasOwnSize(item) && !item.declaresColor && heldControls(item, own: item.controls).isEmpty
            && heldItems(item).allSatisfy(self.isHollow)
        hollow[ObjectIdentifier(item)] = isHollow
        return isHollow
    }

    /// Whether an item declares a size or shows a picture with one.
    func hasOwnSize(_ item: AIMPSkinItem) -> Bool {
        let declared = [item.layout.size, item.layout.sizeMinimal].compactMap { $0 }
        return declared.contains { $0.width > 0 || $0.height > 0 } || flow.image(item.texture)?.hasPixels == true
    }

    /// Whether `AutoHide` hides `item` in a parent `rect`: the parent is smaller than its
    /// `AutoHideParentSizeThreshold` along the item's axis (across for a side panel, or for a client
    /// of a `row`; down for a bar), or, with none given, too small for the item itself.
    func autoHides(_ item: AIMPSkinItem, in rect: CGRect, row: Bool) -> Bool {
        guard item.layout.autoHide else { return false }
        let dock = item.layout.dock
        let across = dock?.isSide == true || (dock == .client && row)
        let room = across ? rect.width : rect.height
        if let threshold = item.layout.autoHideThreshold { return Double(room) < threshold }
        let size = size(item)
        return (across ? size.width : size.height) > room
    }
}

extension AIMPSkinLayout {
    /// A form (or one item of it) laid out at `bounds`: the tree, whether its root is an item drawn
    /// with its own picture rather than the form itself, and what `AutoHide` hid.
    struct Tree {
        let root: Item
        let rootIsItem: Bool
        let autoHidden: Set<String>

        /// What a frame drawn from the tree offers the pointer and the window, read in the order the
        /// painter draws the controls: an item's rect, then its controls (each's targets, rect, hint
        /// and handlers, then those nested in it), then its items.
        var offers: Offers {
            var offers = Offers()
            offers.read(root, isItem: rootIsItem)
            return offers
        }
    }

    struct Offers {
        /// Topmost last, as drawn.
        var targets: [AIMPSkinTarget] = []
        var hints: [(rect: CGRect, text: String)] = []
        var namedRects: [String: CGRect] = [:]
        var mouseHandlers: [AIMPSkinFrame.MouseHandlers] = []
        var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
        var searchFont: AIMPSkinFont?

        fileprivate mutating func read(_ placed: Item, isItem: Bool) {
            if isItem, let name = placed.item.name { namedRects[name] = placed.visible ?? placed.rect }
            // A scroll view takes the wheel under all it holds; what it holds takes clicks only where
            // it is in sight.
            let visible = placed.item.name == nil ? nil : placed.visible
            if let visible, let name = placed.item.name {
                targets.append(AIMPSkinTarget(control: .init(value: Int.min + targets.count), name: name,
                                              kind: .viewScroll(view: name, maxTop: placed.maxTop, thumb: 0), rect: visible))
            }
            let first = targets.count
            placed.controls.forEach { read($0) }
            placed.items.forEach { read($0, isItem: true) }
            guard let visible else { return }
            // Within a scroll view inside another, a target keeps the inner one's clip as well.
            targets.replaceSubrange(first..., with: Self.clipped(Array(targets[first...]), to: visible))
        }

        /// `targets` taking clicks only within `clip` too, over any clip each has; those it hides
        /// wholly go. A target's `rect` stays, for its mask and its local coordinates.
        private static func clipped(_ targets: [AIMPSkinTarget], to clip: CGRect) -> [AIMPSkinTarget] {
            targets.compactMap { target in
                let shown = (target.visibleRect ?? target.rect).intersection(clip)
                guard !shown.isNull, !shown.isEmpty else { return nil }
                var target = target
                if shown != target.rect { target.visibleRect = shown }
                return target
            }
        }

        private mutating func read(_ placed: Control) {
            let control = placed.control, input = control.input
            // A control held in another takes clicks only where it draws, within what holds it
            // (`place`'s `cut`), as AIMP's child windows do.
            targets += placed.cut.map { Self.clipped(placed.targets, to: $0) } ?? placed.targets
            gauges.merge(placed.gauges) { $1 }
            if case .search(_, let font) = placed.look { searchFont = font }
            if let name = control.name {
                namedRects[name] = placed.rect
                // What a right-click does goes on the control's last target (`ContextMenu`).
                if let click = input.rightClick, let index = targets.lastIndex(where: { $0.control == control.id }) {
                    targets[index].rightClick = click
                }
                if let wheel = input.wheel, let index = targets.lastIndex(where: { $0.control == control.id }) {
                    targets[index].wheel = wheel
                }
            }
            if placed.unavailable {
                let note = AIMPSkinLayout.unavailableNote
                hints.append((placed.rect, placed.hint.map { $0.isEmpty ? note : $0 + " (\(note.lowercased()))" } ?? note))
            } else if let hint = placed.hint, !hint.isEmpty {
                hints.append((placed.rect, hint))
            }
            if let name = control.name, input.onMouseEnter != nil || input.onMouseMove != nil || input.onMouseLeave != nil {
                mouseHandlers.append(.init(name: name, rect: placed.rect, enter: input.onMouseEnter, move: input.onMouseMove,
                                           leave: input.onMouseLeave))
            }
            placed.controls.forEach { read($0) }
        }
    }
}

extension AIMPSkinFrame {
    /// `image`, drawn from `layout` at `scale` pixels per skin pixel, and what it offers.
    init(image: CGImage, layout: AIMPSkinLayout.Tree, scale: CGFloat = 1) {
        let offers = layout.offers
        self.init(image: image, targets: offers.targets, alpha: AIMPAlphaMask(image), hints: offers.hints, namedRects: offers.namedRects,
                  mouseHandlers: offers.mouseHandlers, gauges: offers.gauges, searchFont: offers.searchFont,
                  autoHidden: layout.autoHidden, scale: scale)
    }
}
