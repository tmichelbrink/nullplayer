import AppKit

/// A form's size in skin pixels and how the user sizes it: the natural size it is never drawn
/// below, the band along its right and bottom edges a drag sizes it from, a sizing drag under way,
/// and the size maximize goes back to. The view applies it (`AIMPSkinMainView+Sizing`).
struct AIMPSkinSizing {
    /// The form's size in skin pixels.
    var canvas: CGSize
    /// The form's natural size, the smallest it is drawn at.
    private(set) var minimum: CGSize
    /// How near the right and bottom edges a drag sizes the form, in skin pixels; nil for a form
    /// of fixed size.
    private(set) var edge: CGFloat?
    /// A drag sizing the window: where it started on screen, the size then, the edges it moves.
    var drag: (start: NSPoint, size: CGSize, right: Bool, bottom: Bool)?
    /// The size to go back to from maximized; nil while not maximized.
    private(set) var unmaximized: CGSize?
    /// The width the view shown holds the window to (`AllowResizeByWidth` False: Bento's basic
    /// view): the user sizes only its height. Nil when the width is free.
    private(set) var fixedWidth: CGFloat?
    /// The width the pages shown drew at when last measured (`refitPages`).
    private var shownWidth: CGFloat?

    /// A form `minimum` at its natural size, sizable from a band `edge` wide (nil: fixed); `load`
    /// sizes a skin's.
    init(minimum: CGSize = AIMPSkinMainView.unskinnedSize, edge: CGFloat? = nil) {
        self.minimum = minimum
        self.edge = edge
        canvas = minimum
    }

    /// Sizes the form `formName` (nil: the main form) of `skin`, or the unskinned panel: its natural
    /// size, else for a form the user may size the size they last gave it, else the skin's own.
    mutating func load(_ skin: AIMPSkin?, form formName: String?) {
        minimum = skin?.naturalSize(form: formName) ?? AIMPSkinMainView.unskinnedSize
        edge = skin?.index.sizing[formName ?? ""]?.edge
        shownWidth = nil
        // The last skin's maximize and drag are not this one's: restoring from them gave it the
        // last skin's size, and kept it as its own.
        unmaximized = nil
        drag = nil
        fixedWidth = skin.flatMap { AIMPSkinRenderer.fixedWidth($0, form: formName, state: AIMPSkinState()) }
        let initial = skin.flatMap { AIMPSkinRenderer.initialSize($0, form: formName, natural: minimum) }
        let saved = skin.flatMap { Self.savedSize(skin: $0, form: formName) }
        canvas = edge == nil ? minimum : saved.map(clamped) ?? initial.map(clamped) ?? minimum
    }

    /// A fixed form's size for what `state` shows: the natural size grown for items that start
    /// hidden and have been shown (`AIMPSkinRenderer.fittedSize`). A form the user sizes is left.
    mutating func fit(_ skin: AIMPSkin?, form formName: String?, state: AIMPSkinState) {
        guard edge == nil, let skin else { return }
        canvas = AIMPSkinRenderer.fittedSize(skin, form: formName, natural: minimum, state: state)
    }

    /// A form the user sizes, after a click turned one of its tabbed groups: when the pages shown
    /// change its natural size, it takes the new one's width (Bento's 346-px basic view, its wider
    /// advanced one) and at least its height. Nil when nothing changed.
    mutating func refitPages(_ skin: AIMPSkin?, form formName: String?, state: AIMPSkinState) -> Bool {
        guard edge != nil, let skin, var natural = AIMPSkinRenderer.naturalSize(skin, form: formName, state: state),
              let form = skin.index.form(formName) else { return false }
        // As wide as what the pages now shown measure, side by side (Bento's 359-px track info page
        // beside its 342-px deck, which declares no minimum of its own): not the least any page of
        // theirs might need (ClassicPro's 346-px view, though its bottom bar's 503-px page is not shown).
        let shown = skin.withFonts { AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: state)).size(form) }
        // A turn that leaves the width drawn as it was (a visualization's mode, a panel's page of the
        // same size) leaves the window as the user sized it.
        let before = shownWidth ?? skin.withFonts { AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: .init())).size(form).width }
        shownWidth = shown.width
        let fixed = AIMPSkinRenderer.fixedWidth(skin, form: formName, state: state)
        // A panel shown or hidden down the window (Kantaris-Teyp's track-info and wave bars) moves
        // its least height: the window grows by it, or gives it back.
        let grown = natural.height - minimum.height
        let widthMoved = shown.width != before || fixed != fixedWidth
        guard widthMoved || grown != 0 else { return false }
        if shown.width > 0 { natural.width = shown.width }
        minimum = natural
        fixedWidth = fixed
        // A turn that moves only the least height keeps the width the user gave it.
        canvas = clamped(CGSize(width: widthMoved ? natural.width : canvas.width, height: max(canvas.height + grown, natural.height)))
        unmaximized = nil
        return true
    }

    /// At least the natural size, at most four times it.
    func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: fixedWidth ?? min(max(size.width, minimum.width), minimum.width * 4).rounded(),
               height: min(max(size.height, minimum.height), minimum.height * 4).rounded())
    }

    /// The edges a press at `point` sizes, for a form the user may size; `bounds` and `point` in
    /// view points, `scale` view points per skin pixel.
    func edges(at point: NSPoint, in bounds: NSRect, scale: CGFloat) -> (right: Bool, bottom: Bool)? {
        guard let edge = edge.map({ $0 * scale }), bounds.contains(point) else { return nil }
        let right = fixedWidth == nil && point.x >= bounds.maxX - edge, bottom = point.y >= bounds.maxY - edge
        return right || bottom ? (right, bottom) : nil
    }

    /// The canvas the sizing drag asks for with the pointer at `pointer` (screen points): grown
    /// from the top-left corner, clamped; nil while no drag is under way or it asks for no change.
    func dragged(to pointer: NSPoint, scale: CGFloat) -> CGSize? {
        guard let drag else { return nil }
        var size = drag.size
        if drag.right { size.width += (pointer.x - drag.start.x) / scale }
        if drag.bottom { size.height -= (pointer.y - drag.start.y) / scale }
        size = clamped(size)
        return size == canvas ? nil : size
    }

    /// Fills `screen` (points) at `scale`, or goes back to the size before.
    mutating func toggleMaximized(screen: CGSize, scale: CGFloat) {
        if let restore = unmaximized {
            unmaximized = nil
            canvas = clamped(restore)
        } else {
            unmaximized = canvas
            canvas = CGSize(width: fixedWidth ?? max(minimum.width, (screen.width / scale).rounded(.down)),
                            height: max(minimum.height, (screen.height / scale).rounded(.down)))
        }
    }

    /// The size the user last gave `skin`'s form, kept by its name.
    private static func savedSize(skin: AIMPSkin, form formName: String?) -> CGSize? {
        UserDefaults.standard.string(forKey: key(skin: skin, form: formName)).map { NSSizeFromString($0) }
            .flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
    }

    static func save(_ size: CGSize, skin: AIMPSkin, form formName: String?) {
        UserDefaults.standard.set(NSStringFromSize(size), forKey: key(skin: skin, form: formName))
    }

    private static func key(skin: AIMPSkin, form formName: String?) -> String {
        "AIMPSkinSize." + skin.name + (formName.map { "." + $0 } ?? "")
    }
}
