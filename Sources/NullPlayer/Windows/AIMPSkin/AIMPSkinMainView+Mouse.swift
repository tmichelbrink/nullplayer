import AppKit

extension AIMPSkinMainView {
    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only our own: AppKit's tooltip regions are tracking areas too, and removing them all
        // left the skin without tooltips.
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard press.target == nil else { return }
        let point = canvasPoint(event)
        interaction.hovered = drawnFrame?.target(at: point)?.control
        pointerMoved(to: point)
        runMouseHandlers(at: point)
        // A control's hint, else the playing track: AIMP shows both on hover, and skins like
        // Cassette-3D have no title display of their own. Drawn by the view, not AppKit's tooltips,
        // which only show while the app is active.
        let tip = isInside(convert(event.locationInWindow, from: nil)) ? drawnFrame?.hint(at: point)
            ?? [host.player.artist, host.player.title].filter { !$0.isEmpty }.joined(separator: " – ") : ""
        hoverTip.point(at: tip, screenPoint: window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? .zero)
    }

    override func mouseExited(with event: NSEvent) {
        hoverTip.point(at: "", screenPoint: .zero)
        runMouseHandlers(at: nil)
        pointerMoved(to: nil)
        if press.target == nil { interaction.hovered = nil }
    }

    override func mouseDown(with event: NSEvent) {
        hoverTip.point(at: "", screenPoint: .zero)
        if let edges = sizing.edges(at: convert(event.locationInWindow, from: nil), in: bounds, scale: uiScale) {
            sizing.drag = (NSEvent.mouseLocation, sizing.canvas, edges.right, edges.bottom)
            return
        }
        guard isInside(convert(event.locationInWindow, from: nil)) else { return }
        guard let target = drawnFrame?.target(at: canvasPoint(event)) else { return drag.begin(event) }
        let under = target.kind.passesDragsThrough ? draggable(at: canvasPoint(event)) : nil
        press.begin(target, under: under.map { ($0, event.locationInWindow) })
        interaction.pressed = target.control
        if let long = target.longClick {
            press.hold(repeats: false) { [weak self] in self?.runtime?.setCounter(long.counter, to: long.value) }
        } else if let hold = target.holdAction {
            press.hold(repeats: true) { [weak self] in self?.runtime?.onAction?(.action(hold)) }
        }
        pressDown(target, with: event)
        // A press the skin's handler does nothing with (the Onkyos' remote-control panels, whose
        // window NullPlayer lacks) moves the window, as a press on bare skin does. The handler runs
        // off the main thread, so the press is the key's until it answers.
        if case .hold(let down, _) = target.kind {
            let point = canvasPoint(event)
            let arguments = ["X": Double(point.x - target.rect.minX), "Y": Double(point.y - target.rect.minY)]
            let serial = press.serial
            runtime?.runHandler(down, sender: target.name, arguments: arguments) { [weak self] didSomething in
                guard let self, !didSomething, self.press.serial == serial, self.press.target?.control == target.control else { return }
                _ = self.press.end()
                self.interaction.pressed = nil
                self.drag.begin(event)
            }
        }
    }

    /// What a target does as the button goes down: a drag starts, a list row is chosen, the search
    /// box opens. A key acts when the button comes up over it (`activate`).
    private func pressDown(_ target: AIMPSkinTarget, with event: NSEvent) {
        switch target.kind {
        case .slider, .seek: slide(target, to: fraction(target, at: event))
        case .knob(let provider): press.knobStart = (event.locationInWindow, knobValue(provider))
        case .playlist:
            // A click selects a row, Shift a range from the anchor, Command one more or one less; a
            // second click plays it.
            guard let index = playlistIndex(target, at: canvasPoint(event)) else { break }
            skinState.lists.select(index, extending: event.modifierFlags.contains(.shift),
                                   toggling: event.modifierFlags.contains(.command),
                                   shown: host.playlistIndices(matching: skinState.lists.playlistSearch))
            if event.clickCount >= 2 { runtime?.onAction?(.playRow(index)) }
        case .playlistScroll: scrollPlaylist(target, to: canvasPoint(event))
        case .viewScroll: scrollView(target, to: canvasPoint(event))
        case .search(let list): search.begin(list, in: target.rect)
        default: break
        }
    }

    /// The track under `point` in the skin's playlist, through the quick search.
    func playlistIndex(_ target: AIMPSkinTarget, at point: CGPoint) -> Int? {
        guard case .playlist(let rows) = target.kind, let row = rows.row(at: point.y - target.rect.minY) else { return nil }
        let shown = host.playlistIndices(matching: skinState.lists.playlistSearch)
        return shown.indices.contains(row) ? shown[row] : nil
    }

    /// The playlist's thumb to the pointer: its middle there, the rows following.
    func scrollPlaylist(_ target: AIMPSkinTarget, to point: CGPoint) {
        guard case .playlistScroll(let maxTop, let thumb) = target.kind, maxTop > 0 else { return }
        skinState.lists.playlistTop = Int((Self.thumbShare(target.rect, thumb: thumb, at: point) * CGFloat(maxTop)).rounded())
    }

    /// A scroll view's thumb to the pointer: its middle there, the view following.
    func scrollView(_ target: AIMPSkinTarget, to point: CGPoint) {
        guard case .viewScroll(let view, let maxTop, let thumb) = target.kind, thumb > 0, maxTop > 0 else { return }
        skinState.script[view].scrollTop = Double((Self.thumbShare(target.rect, thumb: thumb, at: point) * maxTop).rounded())
    }

    /// How far along a bar's `rect` a thumb `thumb` long sits with its middle at `point`: 0 at the
    /// top, 1 at the foot.
    private static func thumbShare(_ rect: CGRect, thumb: CGFloat, at point: CGPoint) -> CGFloat {
        min(1, max(0, (point.y - rect.minY - thumb / 2) / max(1, rect.height - thumb)))
    }

    /// The wheel scrolls the skin's own playlist under the pointer, three rows a notch.
    override func scrollWheel(with event: NSEvent) {
        let target = drawnFrame?.targets.last(where: { $0.rect.contains(canvasPoint(event)) })
        let lists = skinState.lists
        let rows = event.hasPreciseScrollingDeltas ? -event.scrollingDeltaY / 12 : -event.scrollingDeltaY * 3
        /// The whole rows the wheel moves: a trackpad's fractions of a row add up across its events
        /// (each of a slow swipe is less than one); a notched wheel's three rows a notch as they come.
        func wholeRows() -> Int {
            guard event.hasPreciseScrollingDeltas else { return Int(rows.rounded()) }
            if event.phase == .began { playlistWheelRemainder = 0 }
            playlistWheelRemainder += rows
            let whole = Int(playlistWheelRemainder)
            playlistWheelRemainder -= CGFloat(whole)
            return whole
        }
        /// No further than the last row at the foot of the list, as the renderer stops there.
        func scrolled(_ top: Int, by step: Int, count: Int, visible: Int) -> Int {
            min(max(0, min(top, max(0, count - visible)) + step), max(0, count - visible))
        }
        switch target?.kind {
        case .playlist(let rows):
            let step = wholeRows()
            guard step != 0 else { return }
            skinState.lists.playlistTop = scrolled(lists.playlistTop, by: step, count: host.playlistIndices(matching: lists.playlistSearch).count,
                                                   visible: rows.visible)
        case .playlistScroll(let maxTop, _):
            let step = wholeRows()
            guard step != 0 else { return }
            skinState.lists.playlistTop = min(max(0, min(lists.playlistTop, maxTop) + step), maxTop)
        default:
            // Over a scroll view, even over a key in it, the wheel scrolls the view: 40 px a notch, or
            // the trackpad's own distance.
            let point = canvasPoint(event)
            if let view = drawnFrame?.targets.last(where: { target in
                if case .viewScroll = target.kind { return target.rect.contains(point) } else { return false }
            }), case .viewScroll(let name, let maxTop, _) = view.kind {
                let distance = event.hasPreciseScrollingDeltas ? -event.scrollingDeltaY : -event.scrollingDeltaY * 40
                let top = CGFloat(skinState.script[name].scrollTop ?? 0)
                skinState.script[name].scrollTop = Double(min(max(0, top + distance), maxTop).rounded())
                return
            }
            let steps = wheelStepper.steps(for: event)
            if steps != 0 { wheel(over: target, steps: steps) }
        }
    }

    /// The wheel `steps` notches up (positive) or down over `target`: a control turns; anywhere else
    /// on the main form steps the volume, as in AIMP and NullPlayer's classic skins; a companion's
    /// bare face does nothing. (`AIMPRenderDumpTests`' `AIMP_RENDER_WHEEL` calls this.)
    func wheel(over target: AIMPSkinTarget?, steps: Int) {
        if let target, turn(target, by: steps) { return }
        guard formName == nil else { return }
        runtime?.onAction?(.set(.volume, min(1, max(0, host.player.volume + Double(steps) * 0.05))))
    }

    /// The wheel over a control, `steps` notches up (positive) or down; false when it takes none.
    /// Steps match NullPlayer's classic skins: volume 5%, balance 10% of its swing, an equalizer
    /// band 1 dB, the seek bar 5 seconds; a skin counter moves a position a notch, by the skin's
    /// own `ScrollDelta` expression where it has one (Denon DR-F8's MONITOR).
    func turn(_ target: AIMPSkinTarget, by steps: Int) -> Bool {
        switch target.wheel ?? target.kind {
        case .slider(let provider, _), .knob(let provider):
            if let counter = counter(of: provider) {
                runtime?.moveCounter(counter.name, by: steps)
                return true
            }
            // A notch is a dB on the equalizer's 24-dB scale, else a twentieth.
            let step: Double
            switch provider {
            case .preamp?, .equalizerBand?: step = 1.0 / 24
            default: step = 0.05
            }
            move(target, to: min(1, max(0, host.player.value(for: provider) + Double(steps) * step)))
            return true
        case .seek:
            guard host.player.durationSeconds > 0 else { return true }
            move(target, to: min(1, max(0, host.player.position + Double(steps * 5) / Double(host.player.durationSeconds))))
            return true
        case .counter(let name, let step):
            guard let flow = runtime?.flow else { return false }
            switch step.wheel {
            case .scrollDelta: runtime?.stepCounter(name, by: step, notches: steps)
            case .next:
                // A click-stepped selector (Akai CS-F33's TAPE SELECTOR) stops at its ends.
                guard flow.skin.index.counterModule(name) != nil else { return false }
                runtime?.moveCounter(name, by: steps)
            case .none: return false
            }
            return true
        case .page(let group, let step):
            // A selector over a tabbed group (Pioneer's TAPE switch) steps a page a notch, to its ends.
            guard step.wheel == .next, let flow = runtime?.flow else { return false }
            let count = flow.skin.index.groups[group]?.count ?? 0
            guard count > 0 else { return false }
            skinState.script[group].activePage = min(max(flow.activePage(group) + steps, 0), count - 1)
            return true
        default:
            return false
        }
    }

    /// A control's pointer handlers, as one event: `OnMouseEnter` as the pointer comes over it,
    /// `OnMouseMove` with its place in the control as `X` and `Y`, `OnMouseLeave` as it goes. Nil:
    /// the pointer left the window.
    func runMouseHandlers(at point: CGPoint?) {
        guard let runtime else { return }
        runtime.asOneEvent {
            for handlers in drawnFrame?.mouseHandlers ?? [] {
                let inside = point.map(handlers.rect.contains) ?? false, was = pointerOverHandlers.contains(handlers.name)
                if inside, !was {
                    pointerOverHandlers.insert(handlers.name)
                    if let enter = handlers.enter { runtime.runHandler(enter, sender: handlers.name) }
                }
                if inside, let move = handlers.move, let point {
                    runtime.runHandler(move, sender: handlers.name,
                                       arguments: ["X": Double(point.x - handlers.rect.minX), "Y": Double(point.y - handlers.rect.minY)])
                }
                if !inside, was {
                    pointerOverHandlers.remove(handlers.name)
                    if let leave = handlers.leave { runtime.runHandler(leave, sender: handlers.name) }
                }
            }
        }
    }

    /// Redraws when the pointer enters or leaves a named item or control a skin may show or hide by;
    /// nil: it left the window.
    func pointerMoved(to point: CGPoint?) {
        pointer = point.map { .at($0) } ?? .outside
        let over = point.map { point in Set(hoverRects.filter { $0.value.contains(point) }.keys) } ?? []
        guard over != hoverNames else { return }
        hoverNames = over
        requestRender()
    }

    /// A slider bound to a skin counter (Sony TC-MR2's volume drives `Volume_Counter`, whose script
    /// sets the volume) moves the counter across its `Module`; any other moves the player.
    func slide(_ target: AIMPSkinTarget, to fraction: Double) {
        // A drag past either end stops there: a counter takes only its own positions.
        let fraction = min(1, max(0, fraction))
        switch target.kind {
        case .slider(let provider, _), .knob(let provider):
            if let counter = counter(of: provider) {
                runtime?.setCounter(counter.name, to: Int((fraction * Double(counter.module - 1)).rounded()))
                return
            }
        default: break
        }
        move(target, to: fraction)
    }

    /// A slider, knob or seek bar moved to `value`, 0–1, asked of the player.
    func move(_ target: AIMPSkinTarget, to value: Double) {
        switch target.kind {
        case .seek: runtime?.onAction?(.set(.position, value))
        case .slider(let provider?, _), .knob(let provider?): runtime?.onAction?(.set(provider, value))
        default: break
        }
    }

    /// Where a knob stands, 0–1: its skin counter's position over the counter's range, else the
    /// player's value.
    func knobValue(_ provider: AIMPSkinProvider?) -> Double {
        if let counter = counter(of: provider) { return Double(counter.position) / Double(counter.module - 1) }
        return host.player.value(for: provider)
    }

    /// The skin counter a slider or knob turns (Sony TC-MR2's `Volume_Counter`): its name, positions
    /// and where it stands; nil for one that moves the player.
    func counter(of provider: AIMPSkinProvider?) -> (name: String, module: Int, position: Int)? {
        guard case .named(let name)? = provider, let flow = runtime?.flow, let module = flow.skin.index.counterModule(name) else { return nil }
        let position = AIMPSkinScript.integer(flow.value(name, "Position"))
        return (name, module, position)
    }

    /// The topmost knob, slider or seek bar under a point.
    func draggable(at point: CGPoint) -> AIMPSkinTarget? {
        drawnFrame?.targets.last { $0.kind.isDraggable && $0.rect.contains(point) }
    }

    override func mouseDragged(with event: NSEvent) {
        if sizing.drag != nil { return resize() }
        guard var target = press.target else { return drag.move(event) }
        if let under = press.handOver(at: event.locationInWindow) {
            target = under.target
            interaction.pressed = target.control
            if case .knob(let provider) = target.kind { press.knobStart = (under.start, knobValue(provider)) }
        }
        switch target.kind {
        case .slider, .seek: slide(target, to: fraction(target, at: event))
        case .knob:
            // Up or right turns clockwise; 150 points spans the knob.
            guard let knobStart = press.knobStart else { return }
            let dx = event.locationInWindow.x - knobStart.point.x, dy = event.locationInWindow.y - knobStart.point.y
            slide(target, to: min(1, max(0, knobStart.value + Double(dx + dy) / 150)))
        case .playlistScroll: scrollPlaylist(target, to: canvasPoint(event))
        case .viewScroll: scrollView(target, to: canvasPoint(event))
        // A key shows pressed while the pointer is over it.
        default: interaction.pressed = drawnFrame?.target(at: canvasPoint(event))?.control == target.control ? target.control : nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        if sizing.drag != nil { return endResize() }
        drag.end(event)
        guard let (target, holdFired) = press.end() else { return }
        interaction.pressed = nil
        if let release = target.releaseHandler { runtime?.runHandler(release, sender: target.name) }
        if holdFired { return }
        if case .hold(_, let up) = target.kind {
            if let up { runtime?.runHandler(up, sender: target.name) }
            return
        }
        guard drawnFrame?.target(at: canvasPoint(event))?.control == target.control else { return }
        activate(target, at: convert(event.locationInWindow, from: nil))
    }

    /// What a click on `target` does, once the button comes up over it; a menu opens at `point`.
    /// (The probe's live run clicks through here too.)
    func activate(_ target: AIMPSkinTarget, at point: NSPoint) {
        switch target.kind {
        case .page(let group, let step):
            runtime?.turnPage(group, by: step)
            refitPages()
        case .handler(let handler): runtime?.runHandler(handler, sender: target.name)
        // A click is one notch of the wheel (`Value + ScrollDelta`: Denon DR-F8's MONITOR).
        case .counter(let name, let step): runtime?.stepCounter(name, by: step)
        case .toggle(let item):
            runtime?.toggle(item)
            refitShownItems()
        case .setValue(let provider, let value): runtime?.onAction?(.set(provider, value))
        // A menu the skin builds (AIMP Modern's menu bar), else the one it names (`pmEqualizer`: the
        // presets), else the player's.
        case .menu(.custom(let name)?):
            guard let skin = runtime?.skin, let menu = AIMPSkinCustomMenu(name, index: skin.index) else { return }
            self.menu(menu.items, for: target, at: point).popUp(positioning: nil, at: point, in: self)
        case .menu(.unavailable?): break
        case .menu(let popup): (popup.flatMap { popupMenu?($0, nil, window) } ?? contextMenu()).popUp(positioning: nil, at: point, in: self)
        case .maximize: toggleMaximized()
        case .action(let action): perform(action, at: point)
        // Held keys act as they go down and come up; drags, lists and the search box take their own events.
        case .hold, .slider, .knob, .seek, .playlist, .playlistScroll, .viewScroll, .search, .libraryArea: break
        }
    }

    /// A skin's own menu: each item does what its binding would on a key (`activate`), ticked by its
    /// `State`; an action NullPlayer does not do is shown but not available.
    private func menu(_ items: [AIMPSkinCustomMenu.Item], for target: AIMPSkinTarget, at point: NSPoint) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let flow = runtime?.flow
        for item in items {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let entry: NSMenuItem
            if let press = item.press, !item.isUnavailable {
                let chosen = AIMPSkinTarget(control: target.control, name: target.name, kind: press, rect: target.rect)
                entry = ClosureMenuItem(title: item.caption) { [weak self] in self?.activate(chosen, at: point) }
            } else {
                entry = NSMenuItem(title: item.caption, action: nil, keyEquivalent: "")
                entry.isEnabled = !item.items.isEmpty
                if item.isUnavailable { entry.toolTip = AIMPSkinLayout.unavailableNote }
            }
            if let state = item.state, let flow, flow.value(of: state) != 0 { entry.state = .on }
            if !item.items.isEmpty { entry.submenu = self.menu(item.items, for: target, at: point) }
            menu.addItem(entry)
        }
        return menu
    }

    /// An AIMP action a click asks for. NullPlayer's settings live in its menu, so AIMP's options
    /// open it; AIMP's skin browser is NullPlayer's AIMP skins menu; the quick search key types into
    /// the window's search box.
    private func perform(_ action: AIMPAction, at point: NSPoint) {
        switch action {
        case .options: contextMenu().popUp(positioning: nil, at: point, in: self)
        case .optionSkins: ContextMenuBuilder.buildAIMPSkinsMenu().popUp(positioning: nil, at: point, in: self)
        case .visualNext, .visualPrev: runtime?.stepVisual(by: action == .visualNext ? 1 : -1)
        case .searchQuick, .searchAdvanced:
            guard let box = drawnFrame?.targets.first(where: { if case .search = $0.kind { true } else { false } }),
                  case .search(let list) = box.kind else { return runtime?.onAction?(.action(action)) ?? () }
            search.begin(list, in: box.rect)
        default: runtime?.onAction?(.action(action))
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }

    /// A control whose right-click does something (`ContextMenu`: a knob back to its middle, the
    /// balance to centre) does that; elsewhere the menu.
    override func rightMouseDown(with event: NSEvent) {
        let point = canvasPoint(event)
        guard let target = drawnFrame?.target(at: point) else { return super.rightMouseDown(with: event) }
        // Over the skin's playlist: NullPlayer's playlist menu, the row clicked selected first when it
        // is not already.
        if case .playlist = target.kind {
            let menu = popupMenu?(.playlist, playlistIndex(target, at: point), window) ?? contextMenu()
            menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
            return
        }
        guard let click = target.rightClick else { return super.rightMouseDown(with: event) }
        switch click {
        case .counter(let name, let step):
            guard let position = step.position else { return }
            runtime?.setCounter(name, to: position)
        case .setValue(let provider, let value): runtime?.onAction?(.set(provider, value))
        case .action(let action): runtime?.onAction?(.action(action))
        default: super.rightMouseDown(with: event)
        }
    }

    /// NullPlayer's menu, under the skin's companion windows when it has any.
    func contextMenu() -> NSMenu {
        let menu = ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
        let extra = extraMenuItems?() ?? []
        guard !extra.isEmpty else { return menu }
        menu.insertItem(.separator(), at: 0)
        for item in extra.reversed() { menu.insertItem(item, at: 0) }
        return menu
    }

    override func keyDown(with event: NSEvent) {
        // Delete takes the selected rows out of the skin's own playlist; Return plays the first.
        let selection = skinState.lists.playlistSelection
        if !selection.isEmpty, drawnFrame?.targets.contains(where: { if case .playlist = $0.kind { true } else { false } }) == true {
            if [KeyCode.delete, KeyCode.forwardDelete].contains(event.keyCode) {
                // From the bottom, so each row is where it was.
                for row in selection.sorted(by: >) { runtime?.onAction?(.removeRow(row)) }
                skinState.lists.select(nil)
                return
            }
            if event.keyCode == KeyCode.return, let first = selection.min() { return runtime?.onAction?(.playRow(first)) ?? () }
        }
        if !MainWindowKeys.perform(event) { super.keyDown(with: event) }
    }
}

/// The keys the skin's lists take (`NSEvent.keyCode`).
private enum KeyCode {
    static let `return`: UInt16 = 36
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}
