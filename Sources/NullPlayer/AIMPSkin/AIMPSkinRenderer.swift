import CoreGraphics
import CoreText
import Foundation

/// Draws a form (or one layout item of it) into an image, top-left origin, one skin pixel per
/// point. The layout rules are `reference/layout.md`:
/// - an `item` docks by `Alignment`, each edge's items by `AlignmentLevel`; items with none run
///   down from the top; `laClient` items share what is left along the parent's `LayoutDirection`;
///   `AlignmentMargins` then insets it (`AIMPSkinAlignment`). `AutoHide` takes an item out while its
///   parent is too small for it; a dock site holds a form of the skin's (`AIMPSkinDockSites`);
/// - a `control` is placed by `PlaceInfo`: Delphi anchors (left, top, right, bottom), margins from
///   each side of the parent, and a size;
/// - a `LayoutTabbedGroup` shows its active page; `Visible`/`InitialVisible` `False` hides; a
///   `Visibility` binding hides when its source (an item's visibility, a provider's pin), shaped by
///   its `Expression`, is 0.
enum AIMPSkinRenderer {
    static func frame(_ skin: AIMPSkin, size: CGSize, item rootName: String? = nil, form formName: String? = nil,
                      host: AIMPSkinHostState = .init(), state: AIMPSkinState = .init(),
                      interaction: AIMPSkinInteraction = .init(), scale: CGFloat = 1) -> AIMPSkinFrame? {
        let flow = AIMPSkinDataflow(skin: skin, host: host, state: state)
        // `scale` device pixels per skin pixel: drawn at the screen's resolution, what NullPlayer
        // draws itself (text, the VU meters, the spectrum) is sharp at any UI size.
        let scale = max(1, scale)
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let layout = AIMPSkinLayout(flow: flow, interaction: interaction).tree(size: size, item: rootName, form: formName),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        // The skin's pictures keep their pixels at a whole-number scale, as the window showed them
        // scaled up before; smoothed in between.
        context.interpolationQuality = scale == 1 || scale != scale.rounded() ? .high : .none
        AIMPSkinPainter(flow: flow, context: context).paint(layout.root, asItem: layout.rootIsItem)
        return context.makeImage().map { AIMPSkinFrame(image: $0, layout: layout, scale: scale) }
    }

    /// The size a form is drawn at when nothing else decides it: the first texture down the item
    /// tree that is a picture rather than a tile (`AIMPSkinPolicy.pictureSide`), plus the margins of
    /// the items around it; else the largest `SizeMinimal` met on the way. A window whose every item
    /// starts hidden is measured by what it shows once they show (K-2's open glass lid, shown while
    /// the lid is up).
    /// `state` turns tabbed groups to other pages than their start ones (Bento's advanced view).
    static func naturalSize(_ skin: AIMPSkin, item rootName: String? = nil, form formName: String? = nil,
                            state: AIMPSkinState = .init()) -> CGSize? {
        guard let form = skin.index.form(formName) else { return nil }
        // An item the form does not have has no size, as `frame` draws none for it.
        if let rootName, form.item(named: rootName) == nil { return nil }
        let root = rootName.flatMap(form.item(named:)) ?? form
        let pages = AIMPSkinDataflow(skin: skin, host: .init(), state: state)
        let measure = NaturalSize(skin: skin, page: { pages.activePage($0) })
        var search = measure.search(root, revealing: false)
        if search.measured == nil {
            let revealed = measure.search(root, revealing: true)
            search.meet(revealed)
            search.size = revealed.size
        }
        let docking = AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: state))
        // A main form the user sizes with no picture to go by (its parts flat fills) opens at the
        // least its docked parts allow: Unsquareable's six cover sizes side by side are not its
        // width. One with a picture keeps it (Pulsar's 1040-px arm).
        if rootName == nil, formName == nil, !search.pictured, skin.index.sizing[""] != nil {
            // By the pages it shows; where those measure too little before its scripts run
            // (IpplePlay's), by every page, as all its pages could show.
            let everyPage = AIMPSkinLayout(flow: docking.flow)
            everyPage.leastByEveryPage = true
            for docked in [docking.leastSize(root), everyPage.leastSize(root)]
            where docked.width >= AIMPSkinPolicy.leastWindowSide && docked.height >= AIMPSkinPolicy.leastWindowSide { return docked }
        }
        guard var size = search.measured else { return nil }
        // A window is no smaller than its docked bars' minimums allow (Kenwood KX-800's playlist
        // window: 488-px bars around a 172-px tab column; RealPlayer 11's all-in-one main form: a
        // 360-px playlist between its menu bar and its 88-px transport panel).
        guard rootName == nil else { return size }
        let docked = docking.leastSize(root)
        let pictured = size.width
        size = CGSize(width: max(size.width, docked.width), height: max(size.height, docked.height))
        // A start page the user cannot size across, as wide as the window's picture, holds the window
        // to that width, whatever its other pages need (Bento's 346-px basic view; its wider advanced
        // views come with their own size). One narrower is a part beside others (Akai GX-F90's deck).
        if formName == nil, let width = fixedStartWidth(root, docking: docking), width >= pictured { size.width = width }
        let ceiling = max(AIMPSkinPolicy.listGrowthCeiling, size.height * AIMPSkinPolicy.listGrowthFactor)
        guard let formName else {
            // A main form gives each form docked in it at least its site's `SizeMinimal`, as AIMP holds
            // the window to it: Trident 3's 299-px playlist site under its 242-px deck, which the deck
            // and the site's minimum alone (260 px) left an 18-px strip of. A list the main form holds
            // itself gets room for some rows, as a playlist window's does (Bento's all-in-one view).
            return grown(size, form: nil, flow: docking.flow, ceiling: ceiling) { tree in
                let offers = tree.offers
                let sites = skin.index.sites.keys.compactMap { name -> CGFloat? in
                    guard let rect = offers.namedRects[name], case .item(let site)? = skin.index.byName[name],
                          let minimal = site.layout.sizeMinimal else { return nil }
                    return minimal.height - rect.height
                }.max() ?? 0
                // Only a list the main form holds itself: one in a form docked in a site gets the
                // site's `SizeMinimal` and no more, as AIMP opens it (Euphoria Lux's 100-px
                // playlist in its 216-px site, Kriterya's, W8 Vanilla's).
                // Not in every format (`AIMPSkinDialect.listKeepsRoom`).
                guard skin.index.dialect.listKeepsRoom else { return sites }
                let siteRects = skin.index.sites.keys.compactMap { offers.namedRects[$0] }
                let list = offers.targets.first { target in
                    target.name == AIMPSkinList.playlist.rawValue && !siteRects.contains { $0.contains(target.rect) }
                }.map { AIMPSkinPolicy.listRoom - $0.rect.height } ?? 0
                return max(sites, list)
            }
        }
        // A playlist or library window leaves its list room for some rows (TASCAM CD-RW750's
        // playlist under its cover-art panel), its parts sized by their pictures alone: laid out
        // empty, it grows by what the list lacks.
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: AIMPSkinState())
        let lists = [AIMPSkinList.playlist.rawValue, AIMPSkinList.libraryTable.rawValue]
        return grown(size, form: formName, flow: flow, ceiling: ceiling) { tree in
            tree.offers.targets.first { lists.contains($0.name) }.map { AIMPSkinPolicy.listRoom - $0.rect.height } ?? 0
        }
    }

    /// The width the view `state` shows holds the window to: a page that says `AllowResizeByWidth`
    /// False and is the window's whole width (Bento's basic view); nil when the user may size it.
    static func fixedWidth(_ skin: AIMPSkin, form formName: String? = nil, state: AIMPSkinState) -> CGFloat? {
        guard let form = skin.index.form(formName) else { return nil }
        return fixedStartWidth(form, docking: AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: state)))
    }

    /// The width of the first shown page down `item`'s tree that says `AllowResizeByWidth` False, as
    /// it measures; nil when none does.
    private static func fixedStartWidth(_ item: AIMPSkinItem, docking: AIMPSkinLayout) -> CGFloat? {
        let index = docking.flow.skin.index
        if item.layout.fixedWidth, let name = item.name, index.tabOf[name] != nil {
            let width = docking.size(item).width
            return width > 0 ? width : nil
        }
        let children = item.isTabbedGroup
            ? item.items.filter { $0.name.flatMap { index.tabOf[$0]?.index } == docking.flow.activePage(item.name ?? "") }
            : item.items
        // Beside side panels the page is the middle of the window, not its width (Web Player's face
        // between its volume and menu panels).
        if children.contains(where: { $0.layout.dock?.isSide == true && $0.savedShown }) { return nil }
        return children.lazy.compactMap { fixedStartWidth($0, docking: docking) }.first
    }

    /// A fixed form's size once items that start hidden have been shown: `natural`, grown to the
    /// height its top items take when laid out with them. AIMP fits such a window to what it holds,
    /// so Cassette-3D's VU meter panel (206 px, overlapping by 36) stacks over the 440-px cassette
    /// in a 610-px window instead of pushing the cassette out of a 440-px one. A form the user sizes
    /// keeps `natural`, as does one with nothing hidden shown or with room already (Denon Classic
    /// Style's units, measured into its frame).
    static func fittedSize(_ skin: AIMPSkin, form formName: String? = nil, natural: CGSize, state: AIMPSkinState) -> CGSize {
        guard skin.index.sizing[formName ?? ""] == nil, let form = skin.index.form(formName) else { return natural }
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: state)
        guard skin.index.hiddenItems.contains(where: { form.item(named: $0) != nil && flow.value($0, "Visibility") != 0 }),
              let tree = AIMPSkinLayout(flow: flow).tree(size: natural, form: formName) else { return natural }
        let rects = tree.offers.namedRects
        let bottom = form.items.compactMap { $0.name.flatMap { rects[$0] }?.maxY }.max() ?? 0
        return CGSize(width: natural.width, height: min(max(natural.height, bottom.rounded(.up)), natural.height * 4))
    }

    /// `size` grown down, in a few steps (as panels may take the first growth) and no taller than
    /// `ceiling`, by what `shortfall` finds the form laid out at it lacks; a pixel short is left, a
    /// rounded share.
    private static func grown(_ size: CGSize, form formName: String?, flow: AIMPSkinDataflow, ceiling: CGFloat,
                              shortfall: (AIMPSkinLayout.Tree) -> CGFloat) -> CGSize {
        var size = size
        for _ in 0..<AIMPSkinPolicy.listGrowthSteps {
            guard Int(size.width) > 0, Int(size.height) > 0,
                  let tree = AIMPSkinLayout(flow: flow).tree(size: size, form: formName) else { break }
            let lack = shortfall(tree)
            guard lack > 1 else { break }
            size.height = min(ceiling, size.height + lack)
        }
        return size
    }

    /// The search `naturalSize` makes down a form's item tree, as it was saved: before anything has
    /// run, each tabbed group on its start page (`AIMPSkinIndex.initialPages`).
    private struct NaturalSize {
        let skin: AIMPSkin
        /// The page each tabbed group shows.
        let page: (String) -> Int

        /// What a search found: the size, when it met a picture (or a row of parts beside each
        /// other); the largest `SizeMinimal` (with the margins around it) met on the way, the first
        /// of an area winning; and whether it met a picture.
        struct Found {
            var size: CGSize?
            var largest = CGSize.zero
            var pictured = false

            /// The size found, else the largest minimum, when it has room.
            var measured: CGSize? { size ?? (largest.width > 0 && largest.height > 0 ? largest : nil) }

            /// Another search's minimums and pictures, made after this one's.
            mutating func meet(_ other: Found) {
                if other.largest.width * other.largest.height > largest.width * largest.height { largest = other.largest }
                pictured = pictured || other.pictured
            }
        }

        /// `item`'s size: its picture's, grown to its ancestors' minimums (`floor`), the margins
        /// around it (`inset`) included. `revealing`: items that start hidden count too.
        func search(_ item: AIMPSkinItem, revealing: Bool, inset: CGSize = .zero, floor: CGSize = .zero) -> Found {
            var found = Found()
            let inset = item.layout.slot(inset)
            var floor = floor
            if let minimum = item.layout.sizeMinimal {
                let own = CGSize(width: minimum.width + inset.width, height: minimum.height + inset.height)
                floor = CGSize(width: max(floor.width, own.width), height: max(floor.height, own.height))
                found.meet(Found(largest: own))
            }
            func grown(_ size: CGSize) -> CGSize {
                CGSize(width: max(size.width + inset.width, floor.width), height: max(size.height + inset.height, floor.height))
            }
            if item.isItem, let image = skin.image(item.texture), AIMPSkinPolicy.isPicture(image) {
                found.size = grown(image.frameSize)
                found.pictured = true
                return found
            }
            let children = AIMPSkinAlignment.participants(item.items, of: item, pages: .active(page),
                                                     index: skin.index) { revealing || AIMPSkinAlignment.startsShown($0, in: skin.index) }
            // Items docked side by side are as wide as all of them (Sony ES-Style Silver 2's panels
            // and display; GX-77's playlist window: a button bar left of the list).
            // Only at the top, or where a part has no picture and only its minimum: elsewhere docked
            // pictures stack (Denon's pages, the speakers' cabinets and cones).
            // Each child's search there, with no inset or floor: reused below where none is inherited,
            // so a tree of side-by-side parts is not searched twice at every level.
            var sideBySide: [Found] = []
            if children.count > 1, children.allSatisfy({ $0.layout.dock?.isSide == true || $0.layout.dock == .client }) {
                var bare = false
                var sizes: [CGSize] = []
                for child in children {
                    let part = search(child, revealing: revealing)
                    sideBySide.append(part)
                    found.meet(part)
                    if let size = part.size {
                        sizes.append(size)
                        continue
                    }
                    bare = true
                    if let minimum = child.layout.sizeMinimal { sizes.append(minimum) }
                }
                if sizes.count == children.count, bare || !item.isItem {
                    found.size = grown(AIMPSkinAlignment.aggregate(zip(children, sizes).map { ($0.layout.dock, $1) }, clients: .share(row: true)))
                    return found
                }
            }
            for (i, child) in children.enumerated() {
                let part = i < sideBySide.count && inset == .zero && floor == .zero ? sideBySide[i]
                    : search(child, revealing: revealing, inset: inset, floor: floor)
                found.meet(part)
                if let size = part.size {
                    found.size = size
                    return found
                }
            }
            return found
        }
    }

    /// The size a window the user sizes opens at before any is saved: its `InitialSize`
    /// (`AIMPSkinIndex.sizing`), each side no smaller than `natural`. Nil for fixed windows and for
    /// none given. The window holds it, as any size, within four times the natural one
    /// (`AIMPSkinSizing.clamped`).
    static func initialSize(_ skin: AIMPSkin, form formName: String? = nil, natural: CGSize) -> CGSize? {
        skin.index.sizing[formName ?? ""]?.initialSize.map {
            CGSize(width: max(natural.width, $0.width), height: max(natural.height, $0.height))
        }
    }
}
