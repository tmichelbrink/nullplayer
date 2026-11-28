import Foundation

extension AIMPSkinControl {
    /// What the pointer does to a control, worked out from its bindings and handlers as the skin
    /// loads: the click target the frame offers is built from it (`AIMPSkinLayout`).
    struct Input: Sendable {
        /// What a press does (`AIMPSkinControl.press`).
        let press: AIMPSkinTarget.Kind?
        /// A `ContextMenu` binding as what a right-click does, nil for a real menu.
        let rightClick: AIMPSkinTarget.Kind?
        /// What the wheel does where it is not what a press does (`AIMPSkinTarget.wheel`).
        let wheel: AIMPSkinTarget.Kind?
        /// What it repeats while held (`ActionOnHold`: PREV and NEXT wind, VOLUME − and + step).
        let holdAction: AIMPAction?
        /// Held, a key sets a skin counter its scripts wind by (Tascam 32's and the Akais' PREV and
        /// NEXT: `BtnPrevHold_Counter` to 1), and its `OnMouseUp` handler stops it.
        let longClick: AIMPSkinTarget.LongClick?
        /// `OnMouseUp`: the handler a key runs when let go.
        let onMouseUp: String?
        /// Handlers for the pointer passing over (the reel decks' position preview).
        let onMouseEnter: String?
        let onMouseMove: String?
        let onMouseLeave: String?
        let hint: Hint?
        /// What its `Action` binding names (`prvVolume`, a skin counter, a tabbed group), and the
        /// value a slider or knob over it moves.
        let source: String?
        let moves: Moves?
        /// A display bound to an `Action` is a key whose value picks its picture (Onkyo TA-2066's
        /// AMPLIFIER, MUSIC LIBRARY and TAPE SELECTOR keys).
        let isActionKey: Bool
        /// A lamp that lights at one position of a skin counter a control selects (Akai CS-F33's
        /// three reverse-mode LEDs over its REV SELECTOR) picks that position when clicked: a
        /// shortcut AIMP lacks. Counters scripts drive (REW/FF lamps) stay displays.
        let lamp: (counter: String, position: Int)?

        /// The value a slider, knob or key moves: a player value, or an equalizer band found on
        /// the player's scale as each frame draws (`AIMPSkinHostState.eqBand`).
        enum Moves: Sendable {
            case provider(AIMPSkinProvider?)
            case equalizerBand(aimp: Int)
        }

        /// A tooltip: what its `Hint` binding names (an action, the playing track, a value), else
        /// its `Hint` text.
        enum Hint: Sendable {
            case text(String)
            case playingTrack
            /// The volume, after its label.
            case volume(String)
        }

        /// The script handlers and texts a control names, which what it does is worked out from with
        /// its bindings (`press`).
        struct Handlers: Sendable {
            var onClick: String?
            var onMouseDown: String?
            var onMouseUp: String?
            var onMouseEnter: String?
            var onMouseMove: String?
            var onMouseLeave: String?
            /// `PopupMenu`: a menu of AIMP's (`AIMPSkinPopup`) or one the skin builds.
            var popupMenu: String?
            /// `Hint`: a tooltip's text.
            var hint: String?
        }

        /// `className`: a `SliderMasked` with press handlers is a key the wheel turns.
        init(className: String?, handlers: Handlers, bindings: AIMPSkinBindings, index: AIMPSkinIndex) {
            let pressed = Self.press(bindings, handlers: handlers, index: index)
            // A filmstrip selector with its own press handlers is a button the wheel turns: Soot's
            // big play/pause, prev and next (`cmfSbtn…`) play, pause or skip on a click and stop on
            // a long press through `SbtnOnDown` and `SbtnOnUp`, while the wheel steps
            // `SbtnVolumeRelay`, whose script turns the volume up or down.
            if className == "SliderMasked", case .counter? = pressed, let down = handlers.onMouseDown {
                press = .hold(down: down, up: handlers.onMouseUp)
                wheel = pressed
            } else {
                press = pressed
                wheel = nil
            }
            rightClick = Self.rightClick(bindings, index: index)
            holdAction = bindings.all("ActionOnHold").first { $0.pin == "Action" && $0.expression == nil }?.source.flatMap(AIMPAction.init)
            longClick = bindings["ActionOnLongClick"].flatMap { long in
                long.source.flatMap { index.counterModule($0) != nil ? AIMPSkinTarget.LongClick(counter: $0, value: Int(long.expression ?? "") ?? 1) : nil }
            }
            onMouseUp = handlers.onMouseUp
            onMouseEnter = handlers.onMouseEnter
            onMouseMove = handlers.onMouseMove
            onMouseLeave = handlers.onMouseLeave
            hint = Self.hint(bindings, text: handlers.hint, strings: index.strings) ?? Self.actionHint(bindings)
            let action = bindings["Action"]
            source = action?.source
            if let action, let source = action.source {
                if source == "prvEqualizer", let pin = action.pin {
                    // AIMP 4 has 18 bands (`Band1`–`Band18`), AIMP 5 has 20 (`Band0`–`Band19`).
                    moves = pin == "Preamp" ? .provider(.preamp)
                        : pin.hasPrefix("Band") ? Int(pin.dropFirst(4)).map { .equalizerBand(aimp: $0) } ?? .provider(nil) : .provider(nil)
                } else {
                    moves = .provider(AIMPSkinProvider(source))
                }
            } else {
                moves = nil
            }
            isActionKey = action != nil
            if let link = bindings["DisplayValue"], let counter = link.source, link.pin == "Position",
               index.selectorCounters.contains(counter), let position = link.expression.flatMap(Self.selectedPosition) {
                lamp = (counter, position)
            } else {
                lamp = nil
            }
        }

        /// N in a lamp's `Value = N`.
        static func selectedPosition(_ expression: String) -> Int? {
            // `Value == N` is no lamp: the display parser rejects it too.
            let parts = expression.replacingOccurrences(of: " ", with: "").lowercased().split(separator: "=", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "value" else { return nil }
            return Int(parts[1])
        }

        /// What a press does, from the control's `Action` binding:
        /// - an AIMP action (`acPlayerPlay`);
        /// - a tabbed group's `ActivePage`, shaped by the link's `Expression` (`(value+1) mod 3`);
        /// - a tab's `Visibility`: show that tab (Vega's program keys);
        /// - the main form's `Minimize`, the playlist's or library's `Visible`.
        /// A button a script drives names its action on its `Hint` binding instead (Vega MP-120's
        /// transport); a `PopupMenu` opens the menu it names: one the skin builds (`AIMPSkinCustomMenu`),
        /// NullPlayer's like it, else the player menu.
        static func press(_ bindings: AIMPSkinBindings, handlers: Handlers, index: AIMPSkinIndex) -> AIMPSkinTarget.Kind? {
            if let link = bindings["Action"], let source = link.source {
                // What the skin declares under a name comes first: its own counter `acMode`, its page
                // group `prvPages`, are not AIMP's action or player value of that name.
                let declared = index.providers[source] != nil || index.groups[source] != nil || index.byName[source] != nil
                if !declared, let action = AIMPAction(source) { return .action(action) }
                // AIMP providers count 0–100.
                if !declared, let provider = AIMPSkinProvider(player: source), let fixed = Self.fixedValue(link.expression) {
                    return .setValue(provider: provider, value: fixed)
                }
                // No `Expression`: a press turns to the next page, wrapping, as a counter's steps
                // (Kantaris-Teyp's settings: the `>` beside its speaker style number).
                if index.groups[source] != nil, link.pin == "ActivePage" {
                    return .page(group: source, step: AIMPSkinStep(link.expression ?? "Value + 1"))
                }
                if let tab = index.tabOf[source], link.pin == "Visibility" {
                    return .page(group: tab.group, step: AIMPSkinStep(String(tab.index)))
                }
                if index.names.items.contains(source), link.pin == "Visibility" { return .toggle(item: source) }
                // A companion window's key (Technicss' EQ and amplifier, Sony Media Tower's speakers).
                if index.companions.contains(source), link.pin == "Visible" { return .toggle(item: source) }
                if link.pin == "Position", index.providers[source]?.kind.isCounter == true {
                    // No `Expression`: a press steps it on one, wrapping at its `Module` (M5's gray-art
                    // switch toggles its two-position counter).
                    return .counter(name: source, step: AIMPSkinStep(link.expression ?? "Value + 1"))
                }
                switch (source, link.pin) {
                case ("AIMPMainForm", "Minimize"): return .action(.mainMinimize)
                // A window's own maximize key: the window fills the screen and back (the WMP skins'
                // main form, the playlist's or library's window).
                case (let frame, "Maximize") where index.companions.contains(frame) || frame == "AIMPMainForm": return .maximize
                case ("AIMPMainForm", "StayOnTop"): return .action(.mainStayOnTop)
                case (let frame, "Visible"): if let opens = AIMPFormRole(frame).opens { return opens }
                default: break
                }
            }
            if let hint = bindings.all("Hint").lazy.compactMap({ $0.source.flatMap(AIMPAction.init) }).first {
                return .action(hint)
            }
            if let handler = handlers.onClick { return .handler(handler) }
            if let down = handlers.onMouseDown { return .hold(down: down, up: handlers.onMouseUp) }
            return handlers.popupMenu.map { .menu(index.menuNames.contains($0) ? .custom($0) : AIMPSkinPopup($0)) }
        }

        /// A link's fixed `Expression` for a player value, AIMP's 0–100 as 0–1: nil for none or one
        /// that is not a finite number, held to the range (`150` is the top).
        private static func fixedValue(_ expression: String?) -> Double? {
            guard let fixed = expression.flatMap(Double.init), fixed.isFinite else { return nil }
            return min(1, max(0, fixed / 100))
        }

        /// A `ContextMenu` binding: a knob back to its middle (the Akais' bass and treble to 60),
        /// the balance keys to centre, an action.
        private static func rightClick(_ bindings: AIMPSkinBindings, index: AIMPSkinIndex) -> AIMPSkinTarget.Kind? {
            guard let link = bindings["ContextMenu"], let source = link.source else { return nil }
            if let fixed = link.expression.flatMap(Double.init) {
                // A reset no `Int` holds (`1e300`, `inf`) is none.
                if index.counterModule(source) != nil {
                    return Int(exactly: fixed.rounded(.towardZero)).map { .counter(name: source, step: AIMPSkinStep(String($0))) }
                }
                if let provider = AIMPSkinProvider(player: source), let value = Self.fixedValue(link.expression) {
                    return .setValue(provider: provider, value: value)
                }
            }
            if let action = AIMPAction(source), link.pin == "Action" { return .action(action) }
            return nil
        }

        /// A key with no hint of its own that runs an AIMP action AIMP names (AIMP 2's VisPrev and
        /// VisNext): that name, rather than the playing track the window shows over a bare control.
        private static func actionHint(_ bindings: AIMPSkinBindings) -> Hint? {
            guard let link = bindings["Action"], link.pin == "Action", let title = link.source.flatMap(AIMPAction.init)?.title else { return nil }
            return .text(title)
        }

        /// The player values a hint may name, as AIMP's own menus call them.
        static let valueNames = [
            "prvVolume": "Volume", "prvBalance": "Balance", "prvSpeed": "Speed", "prvTempo": "Tempo",
            "prvPitch": "Pitch", "prvEcho": "Echo", "prvReverb": "Reverb", "prvFlanger": "Flanger",
            "prvChorus": "Chorus", "prvTrueBass": "Bass", "prvEnhancer": "Enhancer",
        ]

        private static func hint(_ bindings: AIMPSkinBindings, text: String?, strings: [String: String]) -> Hint? {
            if let link = bindings["Hint"], let source = link.source {
                if let name = AIMPAction(source)?.title { return .text(name) }
                if source == "prvPlayingFileInfo" || source == "prvQFI" { return .playingTrack }
                if AIMPSkinProvider(player: source) != nil, let format = link.textFormat, !format.contains("%") {
                    let label = AIMPSkinLanguage.expanded(format, strings: strings)
                    return source == "prvVolume" ? .volume(label) : .text(label)
                }
                // A player value with no text of its own: its name (Vega MP-120's program keys, each
                // naming the value it picks: Balance, Echo … Pitch), not the playing track.
                if let name = Self.valueNames[source] { return .text(name) }
            }
            return text.map { .text(AIMPSkinLanguage.expanded($0, strings: strings)) }
        }
    }
}
