import AppKit

/// Shows an AIMP skin's main form: blits `AIMPSkinRenderer`'s frame, the same draw path the probe
/// measures, at the UI scale. A control under the pointer draws its hot frame and its pressed frame
/// while held; a press runs on release. Sliders and knobs follow a drag; anywhere else drawn drags
/// the window through `WindowManager`. A transparent pixel is not part of the window. With no skin,
/// an app-authored panel says how to load one.
final class AIMPSkinMainView: NSView {
    static let unskinnedSize = NSSize(width: 360, height: 96)

    /// The companion form this view shows (a skin's speaker or amplifier window); nil for the main
    /// form. Every view draws and takes clicks; the shared runtime runs the skin's timers and scripts.
    var formName: String?
    /// The skin running, shared with the skin's other windows; nil shows the unskinned panel.
    var runtime: AIMPSkinRuntime? {
        didSet {
            guard runtime !== oldValue else { return }
            oldValue?.detach(self)
            runtime?.attach(self)
            skinDidChange()
        }
    }
    /// The player and the skin's own state (tab pages, counters, lists), the runtime's; a view with
    /// none draws no targets, so nothing reaches these but an empty answer.
    var host: AIMPSkinHostState { runtime?.host ?? AIMPSkinHostState() }
    var skinState: AIMPSkinState {
        get { runtime?.state ?? AIMPSkinState() }
        set { runtime?.state = newValue }
    }
    func skinDidChange() {
        generation.skin += 1
        interaction = .init()
        hasContent = false
        search.end()
        sizing.load(runtime?.skin, form: formName)
        sizing.fit(runtime?.skin, form: formName, state: skinState)
        window?.invalidateCursorRects(for: self)
        hoverRects = [:]
        if libraryArea != nil {
            libraryArea = nil
            reportLibraryArea()
        }
        contentRect = CGRect(origin: .zero, size: sizing.canvas)
        invalidateContent()
        renderNow()
        runtime?.updateClock()
    }

    /// Something only this window shows changed (a key's hot or pressed frame, the pointer): the
    /// skin's next tick draws it, as its scripts may read it (`IsActive`).
    func requestRender() {
        if let runtime { runtime.scheduleTick() } else { needsDisplay = true }
    }

    /// The skin's library lists moved, in this view's points (nil: it shows none), with their
    /// colours: NullPlayer's library browser goes over them (`AIMPSkinLibraryHost`).
    var onLibraryArea: ((AIMPSkinMainView, NSRect?, AIMPSkinControl.Library?) -> Void)?
    /// The library lists' area in the last frame, in skin pixels, and their colours.
    private var libraryArea: (rect: CGRect, colours: AIMPSkinControl.Library)?

    /// Items for the top of the context menu (the skin's companion windows).
    var extraMenuItems: (() -> [NSMenuItem])?
    /// NullPlayer's menu like the one a key's `PopupMenu` names.
    /// `clickedRow` is the playlist row a right-click was over; `window` the one the menu opens on.
    var popupMenu: (@MainActor (_ popup: AIMPSkinPopup, _ clickedRow: Int?, _ window: NSWindow?) -> NSMenu)?
    /// Window points per skin pixel.
    var uiScale: CGFloat = 1 { didSet { if uiScale != oldValue { needsDisplay = true } } }
    /// The form's size in skin pixels, and the user's sizing of it.
    var sizing = AIMPSkinSizing()
    /// The part of the canvas anything is drawn in, in skin pixels: the window shows only this.
    /// A stacked skin hides units until asked for (Denon Classic Style shows its deck alone at the
    /// bottom of a 1745-pixel frame), and AIMP's window fits what is shown.
    private(set) var contentRect = CGRect(origin: .zero, size: AIMPSkinMainView.unskinnedSize)
    /// Device pixels per skin pixel the frame is drawn at: the UI size times the screen's backing
    /// scale, so text and what NullPlayer draws (the VU meters) are sharp. Capped at 2: a frame's
    /// cost grows with its area, about 3× at 2 and 11× at 4 over the installed skins (A4 3.2, the
    /// heaviest, past a 30 fps frame at 4); above 2 the frame is scaled up as before.
    var renderScale: CGFloat { min(Self.maximumRenderScale, max(1, uiScale * (window?.backingScaleFactor ?? 1))) }
    static let maximumRenderScale: CGFloat = 2

    /// What the window shows, in skin pixels.
    var displaySize: CGSize { contentRect.size }
    /// Whether the form draws anything, found when its layout is measured (a skin, page or panel
    /// change), not at each frame: the companion windows ask on every state change.
    private(set) var hasContent = false
    /// The shown part changed size: the window should refit.
    var onDisplaySizeChange: (() -> Void)?
    /// Whether the form draws anything changed (measured with its frame, off the main thread).
    var onContentChange: (() -> Void)?
    /// Set when the skin, its state or the form's size changes, so frames measure the content again
    /// until a measured one of the latest content shows.
    private(set) var contentDirty = true
    /// Which skin, and which change of what shows, a frame was asked for: a frame of a skin since
    /// replaced (even by one of the same name, re-imported) is dropped, and only a measured frame
    /// of the latest change settles the content.
    struct Generation: Equatable, Sendable {
        var skin = 0
        var content = 0
    }
    private(set) var generation = Generation()

    /// What shows may have moved: frames measure it until one of this change shows.
    func invalidateContent() {
        contentDirty = true
        generation.content += 1
    }
    /// What a load failure said, shown on the unskinned panel.
    var message: String? { didSet { if runtime == nil { needsDisplay = true } } }

    /// The frame last drawn, and when and how the next is.
    var drawnFrame: AIMPSkinFrame?
    let scheduler = AIMPSkinFrameScheduler()
    var pointerArea: NSTrackingArea?
    let hoverTip = AIMPSkinHoverTip()
    var interaction = AIMPSkinInteraction() { didSet { if interaction != oldValue { requestRender() } } }
    /// The press under way on one of the skin's targets.
    let press = AIMPSkinPress()
    /// The field the skin's quick search box types into.
    private(set) lazy var search = AIMPSkinSearchField(view: self)
    /// The deck and the skin's other windows alike drag through `WindowManager` (docking, snapping).
    var drag = SkinnedWindowDrag()
    /// How many rows the skin's playlist showed in the last frame (`AIMPSkinFrameFeedback.playlistRowsShown`).
    var playlistRowsShown: Int?
    /// The pointer in skin pixels, and the named rects of the last frame, for `IsActive`;
    /// `hoverNames` is what the pointer was last over, to redraw only on a change.
    var pointer = AIMPSkinFrameFeedback.Pointer.outside
    var hoverRects: [String: CGRect] = [:]
    var hoverNames: Set<String> = []
    var pointerOverHandlers: Set<String> = []
    let windowShadow = SkinWindowShadow()
    /// The size of the frame the shadow last followed, and when it was last pulled (`show`).
    private var shadowFrameSize: CGSize?
    private var shadowPulled = -Double.infinity
    var wheelStepper = ScrollWheelStepper()

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("AIMPSkinMainView")
        setAccessibilityRole(.group)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Dropped files

    /// Files, folders, playlists or cue sheets dropped on any of the skin's windows join the
    /// playlist and the first of them plays, as on NullPlayer's classic windows (`PlaylistDrop`).
    /// Cue sheets are read off the main thread; the tracks are added on it.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PlaylistDrop.accepts(droppedURLs(sender)) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard PlaylistDrop.accepts(urls) else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            let named = PlaylistDrop.namedTracks(urls)
            DispatchQueue.main.async {
                PlaylistDrop.gather(urls, named: named) { tracks in
                    let engine = WindowManager.shared.audioEngine
                    let first = engine.playlist.count
                    engine.appendTracks(tracks)
                    if first < engine.playlist.count { engine.playTrack(at: first) }
                }
            }
        }
        return true
    }

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runtime?.updateClock()
        window?.makeFirstResponder(self)
        // A form's view gets its window after it measured its lists (`AIMPSkinFormWindowMaterializer`).
        if libraryArea != nil { reportLibraryArea() }
        guard let window else { return windowShadow.detach() }
        windowShadow.attach(to: window, name: formName.map { "aimp-\($0)" } ?? "aimp") { [weak self] in
            guard let self, let frame = self.drawnFrame else { return [] }
            return [frame.image.cropping(to: frame.imageRect(self.contentRect)) ?? frame.image]
        }
    }

    /// Draws now, outside the skin's tick (a resize follows the pointer frame by frame).
    func renderNow() { render(clock: scheduler.now) }

    /// On screen, or drawn for the probe (no window): a closed window's frames are seen by nobody.
    var isOnScreen: Bool { window?.isVisible ?? drawsWithoutWindow }
    /// Whether, with no window, the view counts as on screen: the probe's views do; a skin form's
    /// view waiting for its window (`AIMPSkinFormWindowMaterializer`) does not.
    var drawsWithoutWindow = true

    /// Draws the window's form at `clock` from the runtime's state; the runtime's tick calls this
    /// for every window once its scripts have run.
    func render(clock: Double) {
        guard let runtime else {
            drawnFrame = nil
            needsDisplay = true
            return
        }
        let drawn = runtime.host(drawnBy: self, clock: scheduler.probeClock ?? clock)
        let input = AIMPSkinFrameScheduler.RenderInput(skin: runtime.skin, size: sizing.canvas, form: formName, host: drawn, state: runtime.state,
                                                       interaction: interaction, scale: renderScale, measures: contentDirty,
                                                       generation: generation)
        scheduler.draw(input) { [weak self] output in
            guard let self, output.generation.skin == self.generation.skin else { return }
            self.show(output, clock: drawn.feedback.clock)
        }
    }

    /// Takes a drawn frame: its hover rects, rows, gauges and measured content, then shows it.
    private func show(_ output: AIMPSkinFrameScheduler.RenderOutput, clock: Double) {
        drawnFrame = output.frame
        // What `AutoHide` hid in this form, for the skin's bindings (a change draws again).
        runtime?.noteAutoHidden(output.frame?.autoHidden ?? [], by: self)
        if let rects = drawnFrame?.namedRects.filter({ runtime?.skin.index.hoverSources.contains($0.key) == true }), rects != hoverRects { hoverRects = rects }
        notePlaylistRows()
        noteLibraryArea()
        runtime?.easeGauges(drawnFrame?.gauges ?? [:], drawnBy: self, clock: clock)
        // The outline the window's shadow follows moves when the layout does (a panel shown, a
        // resize); reels, meters and lamps turning inside it do not move it. Worked out from the
        // whole frame's transparency off the main thread, it was half a playing deck's CPU at 30
        // frames a second, so it follows layout changes, and at most once a second besides for
        // anything a skin animates across its edge.
        let outlineMayMove = output.measured != nil || (drawnFrame?.image).map { CGSize(width: $0.width, height: $0.height) } != shadowFrameSize
        shadowFrameSize = (drawnFrame?.image).map { CGSize(width: $0.width, height: $0.height) }
        // Settled once a measured frame of the latest change shows (or there is no frame to measure).
        if output.generation.content == generation.content, output.measured != nil || output.frame == nil { contentDirty = false }
        if let measured = output.measured {
            if hasContent != (measured.bounds != nil) {
                hasContent = measured.bounds != nil
                onContentChange?()
            }
            let rect = measured.bounds ?? CGRect(origin: .zero, size: measured.size)
            if rect != contentRect {
                contentRect = rect
                onDisplaySizeChange?()
            }
        }
        needsDisplay = true
        if outlineMayMove || clock - shadowPulled >= 1 {
            shadowPulled = clock
            windowShadow.invalidateShape("redraw")
        }
    }

    /// The rows the skin's playlist has room for, as just drawn; a change redraws once more, as the
    /// scroll bar's visibility follows it.
    private func notePlaylistRows() {
        let rows = drawnFrame?.targets.lazy.compactMap { target -> Int? in
            guard case .playlist(_, let rowHeight) = target.kind, rowHeight > 0 else { return nil }
            return max(1, Int(target.rect.height / rowHeight))
        }.first
        guard let rows, rows != playlistRowsShown else { return }
        playlistRowsShown = rows
        runtime?.notePlaylistRows(rows)
        requestRender()
    }

    /// The union of the frame's library lists, passed on when it moves (a resize, a page turned), in
    /// the colours of the largest: the browser over both is mostly where the table was (AIMP Modern
    /// v3.63's narrow white tree beside its wide blue table).
    private func noteLibraryArea() {
        var area: (rect: CGRect, colours: AIMPSkinControl.Library)?
        var largest: CGFloat = -1
        for target in drawnFrame?.targets ?? [] {
            guard case .libraryArea(let colours) = target.kind else { continue }
            let size = target.rect.width * target.rect.height
            let chosen = size > largest ? colours : area?.colours ?? colours
            largest = max(largest, size)
            area = (area.map { $0.rect.union(target.rect) } ?? target.rect, chosen)
        }
        guard area?.rect != libraryArea?.rect || area?.colours != libraryArea?.colours else { return }
        libraryArea = area
        reportLibraryArea()
    }

    /// Tells the host where the library lists are in this view's points now.
    func reportLibraryArea() {
        guard let onLibraryArea else { return }
        guard let area = libraryArea, contentRect.width > 0, contentRect.height > 0 else { return onLibraryArea(self, nil, nil) }
        let x = bounds.width / contentRect.width, y = bounds.height / contentRect.height
        let rect = NSRect(x: (area.rect.minX - contentRect.minX) * x, y: (area.rect.minY - contentRect.minY) * y,
                          width: area.rect.width * x, height: area.rect.height * y).intersection(bounds)
        onLibraryArea(self, rect.isEmpty ? nil : rect, area.colours)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if libraryArea != nil { reportLibraryArea() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let frame = drawnFrame else { return drawUnskinned() }
        let image = frame.image
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        // A frame drawn at the screen's resolution fits as it is; one drawn smaller is scaled up.
        let exact = frame.scale == renderScale && frame.scale > 1
        context.interpolationQuality = exact || uiScale == uiScale.rounded() ? .none : .high
        context.draw(image.cropping(to: frame.imageRect(contentRect)) ?? image, in: bounds)
        context.restoreGState()
    }

    func drawUnskinned() {
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor(white: 0.12, alpha: 1).setFill()
        panel.fill()
        NSColor(white: 0.3, alpha: 1).setStroke()
        panel.stroke()
        let text = message ?? "No AIMP skin selected.\nRight-click › Skins › AIMP › Load Skin…"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.85, alpha: 1),
                                                         .paragraphStyle: style]
        let box = bounds.insetBy(dx: 16, dy: 0)
        let size = (text as NSString).boundingRect(with: box.size, options: .usesLineFragmentOrigin, attributes: attributes).size
        (text as NSString).draw(with: NSRect(x: box.minX, y: bounds.midY - size.height / 2, width: box.width, height: size.height),
                                options: .usesLineFragmentOrigin, attributes: attributes)
    }

    // MARK: - Hit testing, skin pixels

    func canvasPoint(_ event: NSEvent) -> CGPoint { canvasPoint(convert(event.locationInWindow, from: nil)) }

    func canvasPoint(_ point: NSPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: contentRect.minX + point.x * contentRect.width / bounds.width,
                       y: contentRect.minY + point.y * contentRect.height / bounds.height)
    }

    func isInside(_ point: NSPoint) -> Bool {
        guard let drawnFrame else { return bounds.contains(point) }
        return drawnFrame.isOpaque(at: canvasPoint(point))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let local = superview.map({ convert(point, from: $0) }), bounds.contains(local) else { return super.hitTest(point) }
        // The quick search field while it types takes its own clicks, and the library browser over
        // the lists its clicks, scrolls and drags.
        if search.isTyping(at: local) || subviews.contains(where: { !$0.isHidden && $0.frame.contains(local) }) {
            return super.hitTest(point)
        }
        return isInside(local) ? self : nil
    }

    /// The fraction along a slider or seek bar under the pointer.
    func fraction(_ target: AIMPSkinTarget, at event: NSEvent) -> Double {
        let p = canvasPoint(event)
        if case .slider(_, true) = target.kind {
            return Double(1 - (p.y - target.rect.minY) / max(1, target.rect.height))
        }
        return Double((p.x - target.rect.minX) / max(1, target.rect.width))
    }
}
