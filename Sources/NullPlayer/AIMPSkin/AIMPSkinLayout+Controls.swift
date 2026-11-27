import CoreGraphics
import Foundation

extension AIMPSkinLayout {
    /// The controls `item` shows in `rect`, in drawing order. The playlist is a window of its own in
    /// AIMP, over whatever the skin draws beside it (Sony ES-Style Silver 2's scope behind its list),
    /// and its scroll bar over it: the item's playlist draws after its other controls, its scroll
    /// bars last (sized by the form's playlist once the form is laid out: `withScrollBars`).
    func controls(of item: AIMPSkinItem, in rect: CGRect) -> [Control] {
        let held = heldControls(item, own: item.controls)
        // A control wholly outside its item does not show: AIMP 4 and 5's controls are windows inside
        // their item's (RealPlayer 11's equalizer sliders sit below its 65-px panel until the window
        // grows). Not in every format (`AIMPSkinDialect.controlsOutliveItems`).
        let dialectOutlives = skin.index.dialect.controlsOutliveItems
        func outlives(_ control: AIMPSkinControl) -> Bool { dialectOutlives && !control.confined }
        func inside(_ control: AIMPSkinControl) -> Bool {
            guard !outlives(control), let placement = control.placement else { return true }
            return placement.rect(in: rect, moved: control.name.map { flow.state.script[$0].margins } ?? [:]).intersects(rect)
        }
        func isPlaylist(_ control: AIMPSkinControl) -> Bool { if case .playlist = control.kind { true } else { false } }
        func scrolls(_ control: AIMPSkinControl) -> Bool { if case .playlistScrollBar = control.kind { true } else { false } }
        var placed: [Control] = []
        for control in held where !isPlaylist(control) && !scrolls(control) && inside(control) {
            // Its window cuts a cover at the item's edge (W10's 136-px cover strip in its 50-px icon
            // bar lay over the big cover beside it).
            // A confined control is cut there too (`AIMPSkinControl.confined`).
            let cut: Bool
            if case .coverArt = control.kind { cut = !outlives(control) } else { cut = control.confined }
            guard var made = place(control, in: rect, cut: cut ? rect : nil) else { continue }
            // Clicks too stop at the item's edge, a window's: Soot's play/pause, prev and next are
            // 400-px squares over their panels, each taking clicks only within its own.
            if !outlives(control) {
                made.targets = made.targets.compactMap { target in
                    guard !rect.contains(target.rect) else { return target }
                    let shown = target.rect.intersection(rect)
                    guard !shown.isNull, !shown.isEmpty else { return nil }
                    var target = target
                    target.visibleRect = shown
                    return target
                }
            }
            placed.append(made)
        }
        placed += held.filter(isPlaylist).compactMap { place($0, in: rect) }
        placed += held.filter(scrolls).compactMap { place($0, in: rect) }
        return placed
    }

    /// A control placed in `parent`, then the controls nested in it (a `Panel` holding animators);
    /// nil while it is not shown.
    func place(_ control: AIMPSkinControl, in parent: CGRect, cut: CGRect? = nil) -> Control? {
        // As a script restyled it (Unsquareable's light theme recolours its playlist).
        let control = skin.index.control(control, restyledBy: flow.state.script)
        guard flow.isShown(control), let placement = control.placement,
              layingControls.insert(control.id).inserted else { return nil }
        defer { layingControls.remove(control.id) }
        let placed = placement.rect(in: parent, moved: control.name.map { flow.state.script[$0].margins } ?? [:])
        let rect = autoSized(placed, control)
        let image = flow.image(control.picture)
        let (look, targets) = look(control, image: image, in: rect)
        var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
        if case .gauge(let reaction?) = control.kind {
            gauges[control.id] = (flow.boundValue(control, "DisplayValue") ?? 0, reaction.up, reaction.down)
        }
        // The VU meters' needles swing up quickly and fall back slowly, as a VU's do: about a third
        // of a second to rise, twice that to fall (needle positions 0–1 per thirtieth of a second).
        if case .visualization = control.kind, flow.state.script.visualMode == .vu {
            for (channel, level) in [flow.host.feedback.levelL, flow.host.feedback.levelR].enumerated() {
                gauges[control.id.meter(channel)] = (AIMPSkinPainter.needle(level: level), 0.1, 0.05)
            }
        }
        var made = Control(control: control, image: image, placed: placed, rect: rect, cut: cut, look: look, targets: targets,
                           hint: flow.hint(control), gauges: gauges,
                           // What a control holds draws within it, as AIMP clips a control's children
                           // (M5's half-wave bar: a 56-px waveform in a 36-px panel, its lower half cut).
                           controls: heldControls(control, own: control.controls).compactMap {
                               place($0, in: rect, cut: cut.map { $0.intersection(rect) } ?? rect)
                           })
        made.unavailable = Self.unavailable(control, index: skin.index)
        return made
    }

    /// A key that asks for what NullPlayer does not do: an AIMP action it has no counterpart for
    /// (Bento's Convert and Help), or something in a form NullPlayer does not open (M5's lyrics
    /// window, its tray mini player's pages); a knob or slider on a sound effect NullPlayer lacks
    /// (Kantaris-Teyp's speakers' BASS and ENHANCER: `prvTrueBass`, `prvEnhancer`), drawn but not
    /// turned; a key bound to a pin of AIMP's own that nothing here answers (the WMP skins' library
    /// `MLTable.GroupMode` view switch, their playlist tab arrows `PlaylistTabs.ScrollUp`). Keys a
    /// script drives (bound to the skin's own providers, or with handlers) are never so.
    static func unavailable(_ control: AIMPSkinControl, index: AIMPSkinIndex) -> Bool {
        if case .provider(let provider?)? = control.input.moves, provider.isSoundEffect { return true }
        // A key naming such an effect as its hint picks it for another control to turn (Vega
        // MP-120's program keys 1-6: echo, reverb, flanger, chorus, bass, enhancer).
        if case .key(let key) = control.kind, key.isKey, let source = control.bindings["Hint"]?.source,
           AIMPSkinProvider(source).isSoundEffect { return true }
        guard case .key(let key) = control.kind, key.isKey, control.input.onMouseUp == nil else { return false }
        switch control.input.press {
        case .action(let action)?: return !action.isHandled
        case .menu(.unavailable?)?: return true
        case nil:
            guard let source = control.bindings["Action"]?.source else { return false }
            return index.elsewhere.contains(source) || index.providers[source] == nil
        default: return false
        }
    }

    /// A display that sizes its height to its text (`AutoSize` `csHeight`) is as tall as its lines,
    /// down from its top margin, whatever the margins leave it (FLAT DARK's tips: -38 px).
    func autoSized(_ rect: CGRect, _ control: AIMPSkinControl) -> CGRect {
        guard control.kind.key?.role == .textDisplay else { return rect }
        let text = control.text, name = control.name ?? ""
        // A fixed label (no bindings, left-aligned, one line) is as wide as its text: AIMP sized it
        // so where it was drawn (Red Bias 2.0's 39-px " Вид:" box reads " Layout:" in English).
        if !control.bindings.declared, !text.declaresAutoSize, !text.declaresAlignment, !text.wraps, flow.state.script[name].text == nil {
            let width = AIMPSkinText.width(flow.displayText(control), font: text.font, shelf: skin.fontShelf) + 8
            if width > rect.width { return CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height) }
            return rect
        }
        guard text.sizesHeight else { return rect }
        let shown = flow.state.script[name].text.map { AIMPSkinTemplate.format($0, host: flow.host) } ?? flow.displayText(control)
        let lines = shown.isEmpty ? 0 : text.wraps ? AIMPSkinText.lines(shown, font: text.font, width: abs(rect.width), shelf: skin.fontShelf).count : 1
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: abs(rect.width), height: CGFloat(lines) * AIMPSkinText.lineHeight(text.font, shelf: skin.fontShelf))
    }

    // MARK: What a control shows and does

    /// How `control` looks at `rect`, all the painter needs to draw it, and the click targets it offers.
    private func look(_ control: AIMPSkinControl, image: AIMPSkinImage?, in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let name = control.name ?? ""
        let host = flow.host, state = flow.state
        func target(_ name: String, _ kind: AIMPSkinTarget.Kind, rect: CGRect = rect) -> [AIMPSkinTarget] {
            [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)]
        }
        let frames = max(1, image?.frameCount ?? 1)
        switch control.kind {
        case .key(let key):
            return self.key(control, key, image: image, name: name, in: rect)
        // As AIMP 5.40 draws one: a cell a frame wide for each page, from the control's top left,
        // the shown page's in its second frame, the others in its first; a click on a cell shows
        // its page.
        case .pageSelector(let group):
            guard let group, let pages = flow.skin.index.groups[group], !pages.isEmpty, let image else { return (.pageSelector(count: 0, shown: 0), []) }
            let size = image.frameSize
            let fits = size.width > 0 ? min(pages.count, Int(rect.width / size.width)) : 0
            let cells = (0..<fits).flatMap { i in
                target(name, .page(group: group, step: AIMPSkinStep(String(i))),
                       rect: CGRect(x: rect.minX + CGFloat(i) * size.width, y: rect.minY, width: size.width, height: min(size.height, rect.height)))
            }
            return (.pageSelector(count: fits, shown: flow.activePage(group)), cells)
        // The track's rating, five stars across; without a picture, a key's.
        case .rating(let key):
            guard image != nil else { return self.key(control, key, image: image, name: name, in: rect) }
            return (.rating(AIMPSkinScript.integer(flow.boundValue(control, "DisplayValue") ?? 0)), [])
        // The standard playlist a skin places in its own frame: rows from the top, the first the quick
        // search and scrolling leave.
        case .playlist(let style):
            let shown = host.playlistIndices(matching: state.lists.playlistSearch)
            let tracks = host.player.playlist.rows
            // AIMP's two lines a track, a header over each group; AIMP 2's one line (`classic`).
            let metrics = AIMPSkinPlaylistMetrics(style)
            let group = { (position: Int) in tracks[shown[position]].group }
            let rows = Rows(top: state.lists.playlistTop, count: shown.count, room: rect.height,
                            generation: host.player.playlist.generation, search: state.lists.playlistSearch) { position in
                let starts = !style.classic && !group(position).isEmpty && (position == 0 || group(position - 1) != group(position))
                return (starts ? metrics.header : 0, metrics.item)
            }
            // Each header in view totals its own run of rows, not every group of its name.
            var headers: [Int: GroupHeader] = [:]
            for slot in rows.slots where slot.header > 0 {
                let name = group(slot.row)
                let run = (slot.row..<shown.count).prefix { group($0) == name }
                headers[slot.row] = GroupHeader(name: name, count: run.count, seconds: run.reduce(0) { $0 + tracks[shown[$1]].seconds })
            }
            return (.playlist(style, rows: rows, shown: shown, headers: headers),
                    target(AIMPSkinList.playlist.rawValue, .playlist(rows)))
        // The library window's group tree and table: the area NullPlayer's library browser sits over,
        // in the list's fill.
        // Its colours as the theme now gives them (M5's light and dark lists).
        case .libraryTree(let style):
            let style = style.resolved(flow.visibleColor)
            return (.libraryArea(fill: style.fill), target(AIMPSkinList.libraryTree.rawValue, .libraryArea(style)))
        case .libraryTable(let style):
            let style = style.resolved(flow.visibleColor)
            return (.libraryArea(fill: style.fill), target(AIMPSkinList.libraryTable.rawValue, .libraryArea(style)))
        case .playlistScrollBar(let thumb):
            return scrollBar(control, thumb: thumb, in: rect, playlistRows: 10)
        // Sized once its view is laid out (`withScrollBars`).
        case .viewScrollBar:
            return (.scrollBar(thumb: nil, length: 0, share: nil), [])
        // A list's quick search box: a click types into it; while the window's field types over
        // it, the field shows the text.
        // The library's search boxes have no stand-in: the library browser over the lists has its own.
        case .search(let list):
            guard list == .playlist else { return (.search(nil, font: control.text.font), []) }
            let search = state.lists.search(list)
            return (.search(search.isEmpty || state.lists.searchEditing == list ? nil : search, font: control.text.font),
                    target(name.isEmpty ? list.rawValue + "Search" : name, .search(list: list)))
        case .tabControl(let tabs, let manager):
            return (.tabControl(tabs, caption: manager == "prvMusicLibraryManager" ? "Music Library" : AIMPSkinList.playlistName), [])
        case .playlistTabs(let tabs):
            return (.playlistTabs(tabs, playing: host.player.playState == .playing), [])
        case .playlistBox(let font, let centred):
            return (.playlistBox(font: font, centred: centred), [])
        // A filmstrip of needle positions; `DisplayValue` runs 0–100. Where the skin gives it
        // reaction speeds the window eases it (Denon Classic Style's peak bars fall slowly).
        case .gauge:
            let value = host.feedback.gaugeLevels[control.id] ?? flow.boundValue(control, "DisplayValue") ?? 0
            let index = (value / 100 * Double(frames - 1)).rounded()
            return (.frame(AIMPSkinScript.integer(min(max(index, 0), Double(frames - 1)))), [])
        case .animator:
            // A free-running animator's flat last frame is its mask, not a picture (RealPlayer 11's
            // cover-column glows: a picture and a solid block, which cycled as a white flash).
            let bound = control.bindings["AnimationFrameIndex"] != nil
            let shown = !bound && frames > 1 && image?.lastFrameFlat == true ? frames - 1 : frames
            return (.frame(flow.animatorFrame(control, frames: shown)), [])
        case .stateDisplay:
            // The frame its `State` names: a script's (`Counter1.Set('State', …)`), else its binding's,
            // `State` or `DisplayValue` (Technics RS-1700 4K's drums and tape bands, on counters).
            let state = state.animation[name].frame
                ?? AIMPSkinScript.integer(flow.boundValue(control, "State") ?? flow.boundValue(control, "DisplayValue") ?? 0)
            return (.frame(min(max(state, 0), frames - 1)), [])
        case .time(let digits):
            let link = control.bindings["DisplayValue"]
            var seconds = max(0, AIMPSkinScript.integer(link.map { flow.value(of: $0) } ?? Double(host.player.elapsedSeconds)))
            // A clock (`prvSystemTime`) reads hours and minutes where a track time reads minutes and
            // seconds: in fewer than eight places, its minutes of the day, so 14:05 is not 05:00.
            if case .player(.timeOfDay)? = link?.read, (digits.places ?? 0) < 8 { seconds /= 60 }
            return (.time(seconds: seconds, digits), [])
        case .digits(let digits):
            return self.digits(control, digits, image: image, name: name, in: rect)
        case .equalizer(let preamp, let curve): return (.equalizer(preamp: preamp, curve: curve), [])
        case .coverArt(let cover): return (.coverArt(cover), [])
        case .glass(let blur, let tint): return (.glass(blur: blur, tint: tint), [])
        case .waveform(let background, let content):
            return (.waveform(peaks: host.player.waveform, played: host.player.position, background: flow.color(background),
                              content: flow.color(content)),
                    target(name, .seek))
        case .waveForm(let trace): return (.waveForm(trace), [])
        case .spectrogram(let spectrogram):
            let picture = AIMPSkinSpectrogram.image(host.feedback.spectrogram, clock: host.feedback.clock,
                                                    width: Int(rect.width), height: Int(rect.height),
                                                    content: flow.color(spectrogram.content) ?? 0xFFFF_FFFF,
                                                    flippedHorizontally: spectrogram.flippedHorizontally,
                                                    flippedVertically: spectrogram.flippedVertically)
            return (.spectrogram(background: flow.color(spectrogram.background), picture: picture), [])
        case .visualization(let spectrum, let cover): return (.visualization(spectrum, cover: cover), [])
        case .spectrum(let spectrum): return (.spectrum(spectrum), [])
        case .selector:
            return selector(control, image: image, name: name, in: rect)
        // A seek bar bound to the track's `Waveform` draws it, once NullPlayer has worked it out (M5's
        // wave progress bars): played part in `ColorProgress`, else AIMP's orange; the rest in
        // `Color`, else a half-clear grey the bar's times read over; its thumb, a line, where it plays.
        case .slider(let slider) where slider.isSeek && control.bindings["Waveform"] != nil && !host.player.waveform.isEmpty:
            return (.waveform(peaks: host.player.waveform, played: host.player.position, background: nil,
                              content: flow.visibleColor(slider.progressColor) ?? 0xFFFF_970A,
                              rest: flow.visibleColor(slider.color) ?? 0x8080_8080,
                              thumb: flow.image(slider.thumb)), target(name, .seek))
        case .slider(let slider):
            let fraction = slider.isSeek ? host.player.position
                : control.input.source.flatMap { p in skin.index.counterModule(p).map { flow.value(p, "Position") / Double($0 - 1) } }
                ?? host.player.value(for: flow.provider(control))
            let kind: AIMPSkinTarget.Kind = slider.isSeek ? .seek : .slider(provider: flow.provider(control), vertical: slider.isVertical)
            // A sound effect NullPlayer lacks (Hameleon's CHORUS, ECHO…) is drawn at rest, not dragged.
            let locked = flow.provider(control)?.isSoundEffect == true
            return (.slider(slider, fraction: fraction, thumb: flow.image(slider.thumb)), locked ? [] : target(name, kind))
        }
    }

    /// The playlist's scroll bar: the thumb as long as the share of the playlist's rows in view.
    private func scrollBar(_ control: AIMPSkinControl, thumb: String?, in rect: CGRect, playlistRows: Int) -> (Look, [AIMPSkinTarget]) {
        let lists = flow.state.lists
        let total = flow.host.playlistIndices(matching: lists.playlistSearch).count, maxTop = max(0, total - playlistRows)
        let picture = flow.image(thumb)
        let length = min(rect.height, max(picture?.frameSize.height ?? 8, rect.height * CGFloat(playlistRows) / CGFloat(max(1, total))))
        let top = min(max(0, lists.playlistTop), maxTop)
        return (.scrollBar(thumb: picture, length: length, share: maxTop > 0 ? CGFloat(top) / CGFloat(maxTop) : nil),
                [AIMPSkinTarget(control: control.id, name: "PlaylistScrollBar", kind: .playlistScroll(maxTop: maxTop, thumb: length), rect: rect)])
    }

    /// A scroll view's bar: the thumb as long as the share of the view in sight, where it is scrolled.
    private func viewScrollBar(_ control: AIMPSkinControl, view: String, scroll: Scroll, thumb: String?,
                               in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let picture = flow.image(thumb)
        let length = min(rect.height, max(picture?.frameSize.height ?? 8, rect.height * scroll.visible / max(1, scroll.content)))
        return (.scrollBar(thumb: picture, length: length, share: scroll.maxTop > 0 ? scroll.top / scroll.maxTop : nil),
                [AIMPSkinTarget(control: control.id, name: view + "ScrollBar",
                                kind: .viewScroll(view: view, maxTop: scroll.maxTop, thumb: length), rect: rect)])
    }

    /// `tree` with each playlist scroll bar sized by the rows of the playlist laid out last before
    /// it, in drawing order (ten before any): the bar may sit in another item than its list (21 of
    /// the gate set's playlist windows).
    func withScrollBars(_ tree: Item) -> Item {
        var shown = 10
        func resized(_ control: Control) -> Control {
            var control = control
            if case .playlist(_, let rows, _, _) = control.look { shown = rows.visible }
            if case .playlistScrollBar(let thumb) = control.control.kind {
                (control.look, control.targets) = scrollBar(control.control, thumb: thumb, in: control.rect, playlistRows: shown)
            }
            if case .viewScrollBar(let view, let thumb) = control.control.kind, let scroll = scrolls[view] {
                (control.look, control.targets) = viewScrollBar(control.control, view: view, scroll: scroll, thumb: thumb, in: control.rect)
            }
            control.controls = control.controls.map(resized)
            return control
        }
        func resized(_ item: Item) -> Item {
            var item = item
            item.controls = item.controls.map(resized)
            item.items = item.items.map(resized)
            return item
        }
        return resized(tree)
    }

    /// A digit strip; a key drawn as one (Sony TC-RX80's EQ, MUTE, RANDOM and LOOP: out, latched,
    /// held) shows its last frame while held down.
    private func digits(_ control: AIMPSkinControl, _ digits: AIMPControlClass.Digits, image: AIMPSkinImage?, name: String,
                        in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let input = control.input
        let look = Look.digits(value: flow.boundValue(control, "DisplayValue") ?? 0, digits)
        func target(_ kind: AIMPSkinTarget.Kind, rect: CGRect = rect) -> [AIMPSkinTarget] {
            [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)]
        }
        if input.isActionKey, interaction.pressed == control.id, let image, image.frameCount > 2 {
            return (.frame(image.frameCount - 1), input.press.map { target($0) } ?? [])
        }
        // A display bound to an `Action` is a key whose value picks its picture (Onkyo TA-2066's
        // AMPLIFIER, MUSIC LIBRARY and TAPE SELECTOR keys).
        if input.isActionKey, let kind = input.press { return (look, target(kind)) }
        // A lamp that picks its counter's position; the LEDs are a few pixels, so the click lands
        // within a margin of them.
        if let lamp = input.lamp {
            return (look, target(.counter(name: lamp.counter, step: AIMPSkinStep(String(lamp.position))), rect: rect.insetBy(dx: -10, dy: -10)))
        }
        return (look, [])
    }

    /// A filmstrip slider: its position, and what a click or drag on it does.
    private func selector(_ control: AIMPSkinControl, image: AIMPSkinImage?, name: String, in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let source = control.input.source
        let frames = max(1, image?.frameCount ?? 1)
        func target(_ kind: AIMPSkinTarget.Kind) -> [AIMPSkinTarget] { [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)] }
        // A selector over a tabbed group (Pioneer's TAPE switch): its page picks the position,
        // and a click steps to the next.
        if let group = source, let pages = skin.index.groups[group], pages.count > 1 {
            return (.frame(Self.frame(of: flow.activePage(group), among: pages.count, frames: frames)),
                    target(.page(group: group, step: AIMPSkinStep("(value+1) mod \(pages.count)"))))
        }
        // A selector over a skin counter (Akai CS-F33's TAPE SELECTOR, DISPLAY MODE and REV
        // SELECTOR): its position picks the frame. A few positions step by click; a knob's many
        // (the GX-F90's and Teac's bass and treble, 121 quarter-dB steps) turn by dragging.
        if let counter = source, let module = skin.index.counterModule(counter) {
            let position = min(max(AIMPSkinScript.integer(flow.value(counter, "Position")), 0), module - 1)
            // One with its own press handlers runs them on a click, the wheel stepping the counter
            // (`Input.wheel`: Soot's play/pause).
            let stepped: AIMPSkinTarget.Kind = module > 12 ? .knob(provider: .named(counter)) : .counter(name: counter, step: AIMPSkinStep("Value + 1"))
            let press = control.input.wheel != nil ? control.input.press ?? stepped : stepped
            return (.frame(Self.frame(of: position, among: module, frames: frames)), target(press))
        }
        // A filmstrip of a player value (a knob's rotation): the value picks the frame. Its last
        // frame is its mask (grey by angle: AIMP reads a turn from it), not a position
        // (Mayak-120's knobs: 101 positions and a mask).
        let provider = flow.provider(control)
        let positions = max(1, frames - 1)
        let frame = AIMPSkinScript.integer((flow.host.player.value(for: provider) * Double(positions - 1)).rounded())
        // A sound effect NullPlayer lacks (Pioneer CT-F1000's FLANGER and CHORUS) is drawn, not turned.
        // So is a strip whose last frame is no mask grey by angle (in colour, or flat): a level icon,
        // every frame a picture (WMP12 SB's speaker over its volume, laid over its mute switch,
        // which takes the click).
        let masked = image.map { $0.lastFrameGrey && !$0.lastFrameFlat } ?? false
        guard let provider, provider != .position, !provider.isSoundEffect, masked,
              source.flatMap(AIMPSkinProvider.init(player:)) != nil else { return (.frame(frame), []) }
        return (.frame(frame), target(.knob(provider: provider)))
    }

    /// The frame showing `position` of `count` in a strip of `frames`: one frame per position (plus
    /// a mask) maps straight; otherwise the positions spread over the turns (Technicss' tape
    /// selector: 7 over 91; the GX-F90's tone knobs: 121 over 101).
    static func frame(of position: Int, among count: Int, frames: Int) -> Int {
        let turns = max(1, frames - 1)
        guard turns != count, frames != count else { return position }
        return Int((Double(position) / Double(max(1, count - 1)) * Double(turns - 1)).rounded())
    }

    /// A key's or picture's frame and caption, and the click target a key offers.
    private func key(_ control: AIMPSkinControl, _ key: AIMPControlClass.Key, image: AIMPSkinImage?, name: String,
                     in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        // Buttons stack normal, hot, pressed (and disabled) frames. A switch has a run of
        // `FramesPerState` of them per state, off then on; it is on while its action's `State` is.
        // `Frame` fixes the picture (an AIMP 3.0 skin's lit playlist tab).
        let input = control.input, interaction = interaction
        let caption = key.showsText ? flow.text(control) : ""
        // A left-aligned key whose caption opens with spaces leaves them for its centred glyph
        // (Unsquareable's radios: a 22-px circle, then "       Light", in a box as wide as its words).
        let glyphFirst = key.isKey && image?.fill == .center && control.text.isLeftJustified && flow.displayText(control).first == " "
        func look(_ frame: Int) -> Look { .key(key, frame: frame, caption: caption, glyphFirst: glyphFirst) }
        var frame = key.fixedFrame
        guard let press = input.press else { return (look(frame), []) }
        // Only keys have hot and pressed frames: a display that opens a menu (SL-1200's
        // `Menu_Mask` over its label) keeps its picture under the pointer.
        if key.isKey {
            frame = interaction.pressed == control.id ? 2 : interaction.hovered == control.id ? 1 : 0
        }
        // A switch, or a button with a strip per state (SL-1200's shuffle and repeat keys, GX-R60's
        // slide switches over a counter), shows the run of frames for its `State`: its binding,
        // else its action's.
        let isButton = key.role == .button
        // `FramesPerState` of none or fewer is not a run: read as undeclared (0 trapped the mask's
        // remainder below), and no run is longer than a picture may have frames.
        let declaredPerState = key.framesPerState.flatMap { (1...AIMPSkinPolicy.imageSide).contains($0) ? $0 : nil }
        var perStateFrames = declaredPerState ?? (key.role == .switch ? 3 : 0)
        var state = flow.boundValue(control, "State")
        // A key bound to a `State` with a switch's seven frames (three off, three on, the mask)
        // is a switch: Aiwa AD-M700's PLAYLIST lever stays at SHOW while the playlist is.
        // One that also turns itself off (`Accessibility`) is a radio key instead: off it shows its
        // first three frames, chosen it is off and shows the fourth, lit (M5's skin-settings dots).
        if perStateFrames == 0, isButton, state != nil, image?.frameCount == 7, control.bindings["Accessibility"] == nil {
            perStateFrames = 3
        }
        // Eight frames bound to a `State`: a key's four (normal, hot, pressed, disabled) off,
        // then on (Unsquareable's customize radios; Kantaris-Teyp's settings check boxes, switches,
        // which as three a state showed their disabled box checked and their checked one hovered).
        // More, in whole runs of four and not of three, over a tabbed group's page, are a run per
        // page: Kantaris-Teyp's numbered keys, 01 to 29 (116 frames). Over a counter a frame each
        // is a state (AIMPshield's material overlays, a texture a position).
        let count = image?.frameCount ?? 0
        let onPage = control.bindings["State"]?.pin == "ActivePage"
        if isButton || key.role == .switch, state != nil, declaredPerState == nil,
           count == 8 || (onPage && count > 8 && count % 4 == 0 && count % 3 != 0) { perStateFrames = 4 }
        // Six: three (normal, hot, pressed) off, then on (Bento's shuffle and repeat, their glyphs
        // lit blue).
        if perStateFrames == 0, isButton, state != nil, image?.frameCount == 6 { perStateFrames = 3 }
        if state == nil, case .action(let action) = press { state = flow.host.pin(action.name, "State") }
        // A script's `State` may be any number: held to a million, so the run it names cannot overflow.
        let stateIndex = min(max(0, AIMPSkinScript.integer(state ?? 0)), 1_000_000)
        // The first frame of the run its `State` shows (0 where it shows none).
        let stateFrame = perStateFrames > 0 && stateIndex > 0
            && (key.role == .switch || (image?.frameCount ?? 0) >= (stateIndex + 1) * perStateFrames) ? stateIndex * perStateFrames : 0
        frame += stateFrame
        // A frame left over after whole runs of state frames is the hit mask: `FramesPerState`
        // per state (4 by default: normal, hot, pressed, disabled), plus one. Pioneer CT-F1000's
        // REW and FF share one rect, each opaque only on its half of the mask.
        let perState = declaredPerState ?? 4
        var mask: Int? = count > perState && (count - 1) % perState == 0 ? count - 1 : nil
        // Four frames are a key's whole set: the last is its disabled glyph, not a mask (W10's
        // toolbar keys hit only on their 54-px glyphs). So are whole runs of them, off then on: Bliss
        // Compact Dark's eight-frame Stop, Play and Pause hit only on their glyphs.
        let wholeRuns = count % perState == 0 || (perStateFrames > 0 && count % perStateFrames == 0)
        if mask == nil, isButton, count > 2, !wholeRuns, image?.lastFrameFlat == true { mask = count - 1 }
        // AIMP hits a key on its pixels: one whose resting picture is empty lets clicks through
        // to what is under it (RealPlayer 11's 209-px A-B key over its whole transport row). Of
        // four frames, two empty, the last drawn is where it is hit: the key drawn in the deck's
        // picture, outlined for the pointer (Akai CS-F33's RESET, an 89-px pressed picture over a
        // 22-px key).
        if mask == nil, isButton, image?.firstFrameBlank == true {
            mask = count == 4 && image?.lastFrameBlank == false ? count - 1 : frame
        }
        if case .hold = press, !isButton, count > 0 {
            // A reel or record a press seeks on (Tascam 32's, SL-1200's) is hit only on its tape or
            // grooves, the picture's last frame (its hover highlight, lit like AIMP's); its square
            // would cover the keys beside it.
            mask = count - 1
            if count > 1, interaction.hovered == control.id, image?.firstFrameBlank == false { frame = count - 1 }
        }
        // A key its `Accessibility` turns off (Kenwood KX-800's PLAY while playing) shows its
        // disabled frame and does nothing.
        if key.isKey, flow.boundValue(control, "Accessibility") == 0 {
            // One drawn in runs of three a state (normal, hot, pressed) has no disabled frame: it
            // shows its state's own. M5's radio dots switch themselves off once chosen, and frame
            // 3 is the first lit one: every dot lit.
            if isButton, count >= 4 { frame = perStateFrames == 3 ? stateFrame : 3 }
            return (look(frame), [])
        }
        // A last frame with nothing drawn in it is no mask: the whole key hits (M5's radio dots and
        // switches, seven frames, the last blank).
        let blankMask = mask == count - 1 && image?.lastFrameBlank == true
        let hitMask = blankMask ? nil : AIMPAlphaMask(mask.flatMap { image?.frame($0) })
        var target = AIMPSkinTarget(control: control.id, name: name, kind: press, rect: rect, mask: hitMask)
        if mask == nil, isButton { target.pixels = AIMPAlphaMask(image?.frame(frame)) }
        target.holdAction = input.holdAction
        target.longClick = input.longClick
        switch press {
        case .action, .menu, .maximize: target.releaseHandler = input.onMouseUp
        default: break
        }
        return (look(frame), [target])
    }
}
