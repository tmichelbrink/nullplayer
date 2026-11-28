import AppKit

/// One borderless window per skin form the skin has open beside its deck (speakers, an amplifier, the
/// skin's equalizer unit, its playlist or library), every one drawing from the skin's one runtime.
///
/// Modelled on `WMPViewWindowMaterializer`:
/// - **The deck is the controller's window.** It is never made, placed or ordered out here.
/// - **Views are made with the skin, windows when first wanted.** Each form's view attaches to the
///   runtime as the skin loads, so whether it draws anything (`hasContent`) is known before it is
///   asked for; its window is made the first time the form is visible, undocked and has content
///   while the deck shows. A form no one opens has no window, so nothing docks, minimizes, raises or
///   snaps to it.
/// - **Placed once:** where the user last left it (`AIMPSkinStore`), else where the skin declares
///   (`AIMPSkin.Companion.origin`, the `Schema.xml` `Placement` or the layout's side), then always
///   `WindowManager.rescuedOrigin`, so a window never opens out of reach. `AIMP_PLACE_TRACE=1` logs it.
/// - **Docking is `WindowManager`'s:** the windows are snap targets of its AIMP branch
///   (`materializedAuxiliaryWindows`), so a drag of the deck carries them and a drag of one snaps it.
/// - **A form in a dock site has no window:** the renderer draws it in its site, and its `Visible` key
///   shows or hides it there (`AIMPSkinDockSites`).
///
/// Per skin, the runtime's `AIMPSkinStore.Skin` keeps each window's top-left and whether each form
/// other than the playlist and library was last shown. Those two follow NullPlayer's playlist and
/// library, whose state is `AppStateManager`'s (`SkinSurfaceRouter`).
@MainActor
final class AIMPSkinFormWindowMaterializer: NSObject, NSWindowDelegate {
    private struct FormWindow {
        let window: SkinnedBorderlessWindow
        var hasBeenPlaced = false
    }

    /// Every form that opens a window of its own, by name, drawing whether shown or not.
    private var views: [String: AIMPSkinMainView] = [:]
    /// The windows made so far, by form name.
    private var windows: [String: FormWindow] = [:]
    private weak var runtime: AIMPSkinRuntime?
    /// What is kept of the skin running (its runtime's); nil while none is up, or for one that keeps nothing.
    private var records: AIMPSkinStore.Skin?
    /// Whether each recordable form was last shown, as stored for this skin.
    private var recorded: [String: Bool] = [:]
    /// Off until the skin is up, so neither a teardown's hides nor a load's carry are recorded.
    var recordsVisibility = false
    /// What one of the forms draws changed size or content: the controller shows and hides by it.
    var onContentChange: (() -> Void)?
    /// A form's window was ordered out (`update`): the library browser it may hold goes back to a view
    /// still on screen.
    var onFormHidden: ((AIMPSkinMainView) -> Void)?

    /// The form windows made so far, shown or not, for `WindowManager`'s AIMP branches.
    var materializedAuxiliaryWindows: [NSWindow] { windows.values.map(\.window) }

    /// The window showing `form`, if it has one yet.
    func window(for form: String) -> NSWindow? { windows[form]?.window }

    // MARK: - The skin's forms

    /// Puts away the outgoing skin's windows and makes a view for each of the forms of `runtime`'s
    /// skin that opens a window (none for nil), drawing from `runtime` like `main`, whose menus they
    /// share. What is kept of the skin is the runtime's (`AIMPSkinRuntime.records`).
    func rebuild(runtime: AIMPSkinRuntime?, like main: AIMPSkinMainView) {
        teardown()
        self.runtime = runtime
        records = runtime?.records
        recorded = records?.visibility ?? [:]
        for companion in runtime?.skin.companions ?? [] where companion.opensWindow {
            let view = AIMPSkinMainView()
            view.formName = companion.name
            // Until it has a window it draws only to measure what it shows.
            view.drawsWithoutWindow = false
            view.runtime = runtime
            view.uiScale = main.uiScale
            view.extraMenuItems = main.extraMenuItems
            // Teac Audio System's PRESETS key is on its equalizer window.
            view.popupMenu = main.popupMenu
            view.playlistCommands = main.playlistCommands
            view.onLibraryArea = main.onLibraryArea
            view.onContentChange = { [weak self] in self?.onContentChange?() }
            views[companion.name] = view
        }
    }

    /// Seeds `state` with whether each form other than the playlist and library was last shown with
    /// this skin. A form never recorded keeps the skin's own `InitialVisible`. Run before the skin's
    /// load scripts, which may still change it.
    func restoreVisibility(of skin: AIMPSkin, into state: inout AIMPSkinState) {
        for companion in skin.companions where Self.isRecordable(companion) {
            if let visible = recorded[companion.name.lowercased()] { state.script[companion.name].visible = visible }
        }
    }

    /// Orders out and forgets the skin's windows and views. The deck's window is the controller's and
    /// is left alone.
    func teardown() {
        recordsVisibility = false
        for form in windows.values {
            form.window.orderOut(nil)
            form.window.delegate = nil
            form.window.contentView = nil
        }
        for view in views.values { view.runtime = nil }
        windows = [:]
        views = [:]
        runtime = nil
        records = nil
        recorded = [:]
    }

    /// Shows the forms `flow` has visible, undocked and drawing something while the deck shows, making
    /// each form's window the first time; hides the rest. Records which forms are shown once the skin
    /// is up (`recordsVisibility`).
    func update(_ flow: AIMPSkinDataflow, deck: NSWindow) {
        for (name, view) in views {
            let visible = flow.isVisible(name)
            if recordsVisibility { record(visible, form: name, skin: flow.skin) }
            let wanted = deck.isVisible && visible && !flow.isDocked(name) && view.hasContent
            guard wanted != (windows[name]?.window.isVisible ?? false) else { continue }
            guard wanted else {
                windows[name]?.window.orderOut(nil)
                onFormHidden?(view)
                continue
            }
            // Off screen it was not drawn (`AIMPSkinRuntime.tick`): it shows a frame of now.
            view.renderNow()
            let window = windows[name]?.window ?? materialize(name, view: view, flow: flow)
            Self.fit(window, to: view)
            if windows[name]?.hasBeenPlaced == false, let form = flow.skin.companions.first(where: { $0.name == name }) {
                windows[name]?.hasBeenPlaced = true
                place(window, as: form, beside: deck, scale: view.uiScale)
            }
            if window.isMiniaturized { window.deminiaturize(nil) } else { window.orderFront(nil) }
            // Its lists were reported before its window showed, which the library browser refuses
            // while the deck holds it (`AIMPSkinLibraryHost.libraryArea`); on screen, it may take it.
            view.reportLibraryArea()
        }
    }

    /// The form's window, made once, showing its view.
    private func materialize(_ name: String, view: AIMPSkinMainView, flow: AIMPSkinDataflow) -> SkinnedBorderlessWindow {
        let window = SkinnedBorderlessWindow(contentRect: NSRect(origin: .zero, size: view.displaySize),
                                             styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.isOpaque = false
        // In the space its frames are drawn in, as the main window (`AIMPSkinMainWindowController`).
        window.colorSpace = .sRGB
        // The view casts the skin's own shadow, from what it draws (`SkinWindowShadow`).
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.title = flow.skin.companions.first { $0.name == name }?.title ?? name
        window.setAccessibilityIdentifier("AIMPSkinForm_\(name)")
        window.delegate = self
        window.contentView = view
        view.onDisplaySizeChange = { [weak window, weak view] in
            guard let window, let view else { return }
            Self.fit(window, to: view)
        }
        windows[name] = FormWindow(window: window)
        return window
    }

    /// Whether `form`'s shown or hidden is kept per skin: the playlist and library follow NullPlayer's.
    private static func isRecordable(_ form: AIMPSkin.Companion) -> Bool { form.opensWindow && form.role == .other }

    private func record(_ visible: Bool, form name: String, skin: AIMPSkin) {
        guard let records, recorded[name.lowercased()] != visible,
              let form = skin.companions.first(where: { $0.name == name }), Self.isRecordable(form) else { return }
        recorded[name.lowercased()] = visible
        records.setVisibility(visible, window: name)
    }

    // MARK: - Size and place

    /// Every form's view reports its library area again (`AIMPSkinMainView.reportLibraryArea`).
    func reportLibraryAreas() {
        for view in views.values { view.reportLibraryArea() }
    }

    /// The UI scale changed: every form draws and fits at it.
    func apply(scale: CGFloat) {
        for view in views.values { view.uiScale = scale }
        for (name, form) in windows { if let view = views[name] { Self.fit(form.window, to: view) } }
    }

    /// Sizes `window` to what `view` shows at its scale, holding its top-left corner: the deck's and
    /// every form window's fit.
    static func fit(_ window: NSWindow, to view: AIMPSkinMainView) {
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: view.displaySize.width * view.uiScale, height: view.displaySize.height * view.uiScale))
        window.setFrameTopLeftPoint(topLeft)
        window.invalidateSkinShadowShape("fit")
    }

    /// The window's one placement: where the user last left it; else where the skin opens it beside
    /// the deck (`clearOf` keeps it wholly on the deck's screen and off the skin's other windows).
    /// Last, a window out of reach is moved onto a screen.
    private func place(_ window: NSWindow, as form: AIMPSkin.Companion, beside deck: NSWindow, scale: CGFloat) {
        var frame = window.frame
        if let topLeft = records?.origin(window: form.name) {
            frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        } else {
            frame.origin = form.origin(size: frame.size, beside: deck.frame, scale: scale)
            if let screen = (deck.screen ?? NSScreen.main)?.visibleFrame {
                let others = windows.values.map(\.window).filter { $0 !== window && $0.isVisible }.map(\.frame)
                frame = Self.clearOf(others, frame, on: screen, deck: deck.frame)
            }
        }
        window.setFrameOrigin(frame.origin)
        if let rescued = WindowManager.shared.rescuedOrigin(for: window) { window.setFrameOrigin(rescued) }
        if ProcessInfo.processInfo.environment["AIMP_PLACE_TRACE"] == "1" {
            NSLog("[aimp/place] %@ %@", form.name, NSStringFromRect(window.frame))
        }
    }

    /// `frame` where the skin puts it, kept wholly on `screen` (Red Bias 2.0's skin settings under its
    /// 1,030-px deck; Tascam Fireone's playlist and library under a deck near the screen's foot). Where
    /// that covers one of `others`, the skin's windows already open (two forms it opens below the
    /// deck at the same place), or, once moved onto the screen, the `deck` it was meant to stand
    /// beside, it goes beside that window instead, right then left, at the first place on the screen
    /// clear of them all. With no such place, clear of `others` alone; with none, where the skin put it.
    static func clearOf(_ others: [NSRect], _ frame: NSRect, on screen: NSRect, deck: NSRect) -> NSRect {
        let wanted = WindowPlacement.rescued(frame, into: screen)
        // Where the skin's own spot overlaps the deck it is the skin's (a lid standing on it).
        if wanted != frame, let clear = firstClear(of: others + [deck], from: wanted, on: screen) { return clear }
        return firstClear(of: others, from: wanted, on: screen) ?? wanted
    }

    /// The first place on `screen` clear of `occupied`, from `start`, stepping beside whatever is in
    /// the way, right then left; nil when there is none.
    private static func firstClear(of occupied: [NSRect], from start: NSRect, on screen: NSRect) -> NSRect? {
        var tried = Set<String>()
        var queue = [start]
        while !queue.isEmpty, tried.count < 64 {
            let candidate = queue.removeFirst()
            guard tried.insert(NSStringFromRect(candidate)).inserted, screen.contains(candidate) else { continue }
            let blocking = occupied.filter { $0.intersects(candidate) }
            if blocking.isEmpty { return candidate }
            for other in blocking {
                queue.append(NSRect(x: other.maxX, y: candidate.minY, width: candidate.width, height: candidate.height))
                queue.append(NSRect(x: other.minX - candidate.width, y: candidate.minY, width: candidate.width, height: candidate.height))
            }
        }
        return nil
    }

    // MARK: - The context menu

    /// The forms that draw anything, checked while shown, for the context menu (AIMP lists them in
    /// its own), whether or not their window was ever made; choosing one shows or hides it.
    func menuItems(_ flow: AIMPSkinDataflow, toggle: @escaping (String, Bool) -> Void) -> [NSMenuItem] {
        flow.skin.companions.compactMap { form in
            guard views[form.name]?.hasContent == true else { return nil }
            let visible = flow.isVisible(form.name)
            let item = ClosureMenuItem(title: form.title) { toggle(form.name, !visible) }
            item.state = visible ? .on : .off
            return item
        }
    }

    // MARK: - NSWindowDelegate, form windows only

    /// The deck keeps `AIMPSkinMainWindowController` as its delegate, so every callback here is a
    /// form window's.
    private func form(of window: NSWindow) -> String? {
        windows.first { $0.value.window === window }?.key
    }

    /// The close command hides the form, as its own close key does.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let name = form(of: sender) else { return true }
        runtime?.setVisible(name, false)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let name = form(of: window),
              windows[name]?.hasBeenPlaced == true, window.isVisible else { return }
        // **Not while the user drags it:** `WindowManager` has put the drag through `windowWillMove`
        // and set the origin itself, and running it again from here would move its docked group a
        // second time (`WMPViewWindowMaterializer` carries the same guard).
        if !WindowManager.shared.isWindowDragInProgress {
            WindowManager.shared.applySnappedPosition(window, to: WindowManager.shared.windowWillMove(window, to: window.frame.origin))
        }
        WindowManager.shared.postWindowLayoutDidChange()
        records?.setOrigin(CGPoint(x: window.frame.minX, y: window.frame.maxY), window: name)
    }

    /// A form window brought forward brings the deck and the rest with it, a turn later, once a
    /// click-activation has finished (W273).
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, form(of: window) != nil else { return }
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isKeyWindow else { return }
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }

    /// Covered or uncovered: the skin's clock runs only while one of its windows is seen.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        runtime?.updateClock()
    }
}
