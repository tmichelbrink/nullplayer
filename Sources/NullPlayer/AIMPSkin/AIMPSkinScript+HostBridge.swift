import Foundation

/// What a script reaches beyond its own variables: the host calls that read the dataflow, and the
/// objects `FindObject` finds (the skin's controls, items and providers, and the player's), with
/// what `Set`, `Get` and `Execute` do to each.
extension AIMPSkinScript {
    /// The calls that read the skin or the player, resolved by name as the script compiles (the
    /// rest are `Builtin`s).
    enum HostCall: Sendable {
        /// `BindingsGetDataAsText(source, pin)`, and `…AsText3(source, pin, expression, format)`
        /// with a link's own `Expression` and `TextFormat` (DEFIX Hi-End's search links read `%T`,
        /// `%R` and `%A` of `prvPlayingFileInfo.FileInfo` this way).
        case dataAsText, dataAsText3
        /// `BindingsGetDataAsInteger`, `…AsFloat`, `…AsBoolean`.
        case dataAsNumber
        /// What scripts store with `ConfigSet` and read back with `ConfigGet(name, default)`.
        case configGet, configSet
        case findObject
        /// The object the script belongs to: the control or provider that runs it.
        case current

        init?(_ key: String) {
            switch key {
            case "bindingsgetdataastext": self = .dataAsText
            case "bindingsgetdataastext3": self = .dataAsText3
            case "bindingsgetdataasinteger", "bindingsgetdataasfloat", "bindingsgetdataasboolean": self = .dataAsNumber
            case "configget": self = .configGet
            case "configset": self = .configSet
            case "findobject": self = .findObject
            case "self": self = .current
            default: return nil
            }
        }
    }

    /// What `FindObject(name)` finds, resolved once: one of the player's values, read as a knob bound
    /// to it reads it (`AIMPSkinProvider`), or the skin's own (an item or control, a `Schema.xml`
    /// provider, an action, a list), whichever the name finds.
    struct HostObject {
        let name: String
        let kind: Kind
        let element: AIMPSkinIndex.Element?
        let provider: AIMPSkinIndex.Provider?

        enum Kind {
            /// The track's position, the volume, the balance, or the speed (AIMP's speed and tempo:
            /// NullPlayer's tempo-preserving speed is both).
            case player(AIMPSkinProvider)
            /// `prvEqualizer`: its `BandValue<n>` and `PreampValue`, in dB.
            case equalizer
            /// An effect NullPlayer lacks (`prvReverb`): only its knob moves, keeping its place.
            case effect
            case skin
        }

        init(_ name: String, in skin: AIMPSkin) {
            self.name = name
            switch AIMPSkinProvider(name) {
            case .named:
                kind = name == "prvEqualizer" ? .equalizer : Self.effects.contains(name) ? .effect : .skin
            case let provider:
                kind = .player(provider)
            }
            element = skin.index.byName[name]
            provider = skin.index.providers[name]
        }

        private static let effects = AIMPSkinProvider.soundEffects

        /// One of the lists the skin's windows draw from NullPlayer's: their style is the skin's to set.
        var list: AIMPSkinList? { AIMPSkinList(rawValue: name) }
    }

    /// A property a script sets or reads with `Set(name, value)` and `Get(name)`. Names are matched
    /// as AIMP writes them: a skin's `'position'` is some other property of its own.
    enum Property {
        case activePage, position, state, visible, enabled, interval, template, opacity, frameIndex, parent, name, tag
        /// A control's text as shown (`DisplayText`).
        case displayText
        /// `PlaceInfo.Margins.Left` … `Bottom`: 0 left, 1 top, 2 right, 3 bottom; nil for another side.
        case margin(Int?)
        /// The equalizer's `PreampValue` and `BandValue<n>` (AIMP's band n).
        case preamp
        case band(Int)
        case other

        init(_ name: String) {
            switch name {
            case "ActivePage": self = .activePage
            case "Position": self = .position
            case "State": self = .state
            case "Visible": self = .visible
            case "Enabled": self = .enabled
            case "Interval": self = .interval
            case "Template": self = .template
            case "BlendingModeOpacity": self = .opacity
            case "FrameIndex": self = .frameIndex
            case "Parent": self = .parent
            case "Name": self = .name
            case "Tag": self = .tag
            case "DisplayText": self = .displayText
            case "PreampValue": self = .preamp
            default:
                if name.hasPrefix("PlaceInfo.Margins.") {
                    self = .margin(["Left", "Top", "Right", "Bottom"].firstIndex(of: String(name.dropFirst(18))))
                } else if name.hasPrefix("BandValue"), let band = Int(name.dropFirst(9)) {
                    self = .band(band)
                } else {
                    self = .other
                }
            }
        }
    }
}

extension AIMPSkinScript.Run {
    typealias Value = AIMPSkinScript.Value
    typealias Unsupported = AIMPSkinScript.Unsupported
    typealias HostObject = AIMPSkinScript.HostObject
    typealias Member = AIMPSkinScript.Member

    func host(_ call: AIMPSkinScript.HostCall, _ args: [Value]) throws -> Value {
        func arity(_ count: Int) throws {
            guard args.count == count else { throw Unsupported(what: "\(call) arguments") }
        }
        switch call {
        case .dataAsText:
            try arity(2)
            // A tabbed group's page reads as its name: Mayak MP-140C builds `Skin.VUAveraged` +
            // 'Green' from its `Colour` group.
            // Through the text reader the four-argument form uses: a page as its name (Mayak MP-140C
            // builds `Skin.VUAveraged` + 'Green' from its `Colour` group), `FileInfo` as the title, a
            // number as its digits.
            return .string(text(of: link(source: args[0].string, pin: args[1].string, expression: "", textFormat: "")))
        case .dataAsText3:
            try arity(4)
            return .string(text(of: link(source: args[0].string, pin: args[1].string, expression: args[2].string,
                                         textFormat: args[3].string)))
        case .dataAsNumber:
            try arity(2)
            return .number(flow.value(args[0].string, args[1].string))
        case .configGet:
            return .string(engine.state.script.config[args.first?.string ?? ""] ?? (args.count > 1 ? args[1].string : ""))
        case .configSet:
            if args.count >= 2 { engine.state.script.config[args[0].string] = args[1].string }
            return .none
        case .findObject:
            return .object(HostObject(args.first?.string ?? "", in: skin))
        case .current:
            return lookup("sender") ?? .none
        }
    }

    /// `target.member(args…)`.
    func method(_ target: Value, _ member: Member, _ args: [Value]) throws -> Value {
        if let handled = try bindingsMethod(target, member, args) { return handled }
        switch (target, member) {
        case (.resource(let id), .set) where args.count == 2:
            if args[0].string == "ID" { engine.state.script.resourceLinks[id] = args[1].string }
            // A resource's other settings are the skin's to keep; nothing here draws them yet.
            return .none
        case (.resource(let id), .get) where args.count == 1:
            if args[0].string == "ID" { return .string(engine.state.script.resourceLinks[id] ?? id) }
            // A resource's own setting (`FindResource('Skin.Default').Get('Value')`: a theme colour).
            let property = skin.resources[engine.state.script.resourceLinks[id] ?? id]?[args[0].string]
            let text = property?["value"] ?? property?.named["Value"]?["value"] ?? ""
            return Double(text).map(Value.number) ?? .string(text)
        case (.object(let object), .set) where args.count == 2:
            try set(object, args[0].string, to: args[1])
            return .none
        case (.object(let object), .get) where args.count == 1:
            return get(object, args[0].string)
        case (.object(let object), .execute):
            try execute(object)
            return .none
        // Docking (`AIMPSkinDockSites`): a form into its site and out to its window, and an item or
        // control into another item (Soot's all-in-one mode, A4 3.2's layouts).
        case (.object(let object), .parent) where args.isEmpty:
            return flow.parent(of: object.name).map { .object(HostObject($0, in: skin)) } ?? .none
        case (.object(let object), .dock) where args.isEmpty:
            engine.state.script[object.name].docked = true
            return .none
        case (.object(let object), .undock) where args.isEmpty:
            engine.state.script[object.name].docked = false
            return .none
        case (.object, .getResourceName), (.resource, .getResourceName):
            return .string(target.string)
        // Update batching and the clipboard: nothing to do here.
        case (_, .beginUpdate), (_, .endUpdate), (_, .copyToClipboard):
            return .none
        // A mouse handler's event: the window only passes the left button on, and whether a handler
        // took the event (`Handled`) changes nothing NullPlayer does next.
        case (.arguments, .get) where args.count == 1:
            if args[0].string == "Button" { return .string("mbLeft") }
            return .number(arguments[args[0].string] ?? 0)
        case (.arguments, .set) where args.count == 2:
            return .none
        // A form event's data (its new size, `PlaceInfo.ActualWidth`): NullPlayer's forms pass none.
        case (.eventData, .get) where args.count == 1:
            return .number(0)
        // A visualization handler's data: one band of the spectrum, 0–100. AIMP's 256 bands, low
        // to high, laid over however many the host has.
        case (.visualData, .spectrum):
            let spectrum = flow.host.feedback.spectrum
            guard !spectrum.isEmpty else { return .number(0) }
            let band = Int(Double(max(0, min(255, AIMPSkinScript.integer(args.last?.number ?? 0)))) / 256 * Double(spectrum.count))
            return .number(spectrum[min(band, spectrum.count - 1)] * 100)
        default:
            throw Unsupported(what: "method \(member)(\(args.map(\.string).joined(separator: ","))) on \(target.described)")
        }
    }

    // MARK: - Objects

    private func set(_ object: HostObject, _ path: String, to value: Value) throws {
        let name = object.name
        switch (object.kind, AIMPSkinScript.Property(path)) {
        case (_, .activePage):
            engine.state.script[name].activePage = AIMPSkinScript.integer(value.number)
        case (.player(let provider), .position):
            setPlayer(provider, value.number)
        // Effects NullPlayer lacks only move their knobs.
        case (.effect, .position):
            engine.ask(.set(.named(name), max(0, min(1, value.number))))
        // The equalizer in dB: `BandValue<n>` (AIMP's band n) and `PreampValue` (the GX-F90's bass
        // and treble knobs shape the low and high bands this way). It has nothing else to set.
        case (.equalizer, .preamp):
            engine.setPreamp(AIMPSkinProvider.preamp.value(script: value.number))
        case (.equalizer, .band(let aimp)):
            if let band = flow.host.player.eqBand(aimp: aimp, aimp5: skin.archive.format == .acs5) {
                engine.setEqualizer(band: band, aimp: aimp, to: AIMPSkinProvider.equalizerBand(band).value(script: value.number))
            }
        case (.equalizer, _):
            break
        case (_, .position):
            // A scripted counter runs its script when it moves (Red Bias 2.0's layout switch sets
            // `ThemeSettingLayout`, whose script docks and undocks the library).
            // `movingCounter` writes the position itself, after keeping the old one: out of budget,
            // the counter stays where it was and this script stops too, so both run again.
            let position = AIMPSkinScript.integer(value.number)
            let moved = AIMPSkinScript.integer(flow.value(name, "Position")) != position
            if moved, object.provider?.kind == .counter(scripted: true) {
                try engine.movingCounter(name, to: position)
            } else {
                engine.state.script[name].counter = position
            }
        case (_, .state) where object.element?.node["class"] == "StateDisplay":
            engine.state.animation[name].frame = AIMPSkinScript.integer(value.number)
        case (_, .visible):
            // Taking the control over afresh, the script's value holds until its `Visibility`
            // bindings next change from where they stand now (`Engine.pushVisibility`), not from the
            // value last seen under an earlier override: Vega MP-120 swaps its stop key on every
            // stop, and a gate value stale from the first swap would undo the second at once. The
            // gate is taken as it stands now, so one that moves before the next frame still ends it.
            if engine.state.script[name].visible == nil {
                engine.state.script[name].visibleGate = engine.visibilityGate(name, flow: flow)
            }
            engine.state.script[name].visible = value.number != 0
        case (_, .enabled):
            engine.state.script[name].timerEnabled = value.number != 0
        case (_, .interval):
            engine.state.script[name].timerInterval = value.number
        case (_, .margin(let side)):
            if let side { engine.state.script[name].margins[side] = value.number }
        case (_, .template):
            engine.state.script[name].text = value.string
        case (_, .opacity):
            engine.state.animation[name].opacity = min(255, max(0, value.number))
        case (_, .frameIndex):
            engine.state.animation[name].frame = AIMPSkinScript.integer(value.number)
            // Outside a frame (a click's handler) there is no clock: the next frame starts the
            // interval (`Engine.stepAnimators`), so the frame set shows for its full delay.
            let clock = flow.host.feedback.clock
            engine.state.animation[name].stepped = clock > 0 ? clock : .infinity
        case (_, .parent):
            // Only into something the skin has that can hold it, and not under itself or anything it
            // holds: a holder that does not exist, or a loop, would take it out of every window. An
            // item goes only into an item; a control into an item or a control. The walk goes to the
            // top, however far.
            guard case .object(let parent) = value, let holder = skin.index.byName[parent.name] else { break }
            if case .item? = object.element, case .control = holder { break }
            var above: String? = parent.name, seen: Set<String> = []
            while let next = above {
                if next == name || !seen.insert(next).inserted { return }
                above = flow.parent(of: next)
            }
            engine.state.script[name].parent = parent.name
        default:
            // Any other property of a control, item or list: kept, and drawn
            // (`AIMPSkinState.Object.properties`). A colour given as a Delphi colour (`$F1F1F1`,
            // no alpha) is opaque. Of anything else (a form, a provider, a name the skin lacks) it
            // is AIMP's own, which nothing here draws: the run goes on.
            if path == "Expression", object.provider?.kind == .concatenator {
                engine.state.script[name].expression = value.string
                return
            }
            guard object.element != nil || object.list != nil else { return }
            let text: String
            if case .number(let number) = value {
                let colour = path.hasSuffix("Color") || path.contains("Color.") || path.contains("Colors.")
                text = colour && !path.hasSuffix(".ID") && number >= 0 && number <= 0xFF_FFFF
                    ? String(AIMPSkinColor.argb(delphi: Int64(number))) : String(AIMPSkinScript.integer(number))
            } else {
                text = value.string
            }
            engine.state.script[name].properties[path] = text
        }
    }

    /// What setting one of the player's values asks of it, from the script's units: the balance
    /// −1…1 (Mayak-232's left and right volume sliders), speed and tempo as multipliers (Kenwood's
    /// effects reset sets them to 1).
    private func setPlayer(_ provider: AIMPSkinProvider, _ value: Double) {
        switch provider {
        // The player's position is the track's: setting it seeks (Technics' counter reset rewinds
        // to 0), asked of the window as `AIMPSkinCommand.seek`.
        case .position: engine.ask(.seek(seconds: value))
        // AIMP centres pitch on 0 where speed and tempo sit on 1: the effect resets of Kenwood
        // KX-4520, Onkyo TA-2066 and Teac V-3RX set Speed 1, Tempo 1, Pitch 0.
        case .volume, .balance, .speed, .pitch: engine.ask(.set(provider, provider.value(script: value)))
        // Never a `.player` object's (`HostObject` makes these four only).
        case .preamp, .equalizerBand, .named:
            break
        }
    }

    private func get(_ object: HostObject, _ path: String) -> Value {
        let name = object.name
        switch (object.kind, AIMPSkinScript.Property(path)) {
        case (.player(.balance), .position):
            return .number(AIMPSkinProvider.balance.script(value: flow.host.player.balance))
        // Speed (and tempo) as a multiplier, pitch about 0: what `Set` takes (`setPlayer`).
        case (.player(.speed), .position):
            return .number(AIMPSkinProvider.speed.script(value: flow.host.player.speed))
        case (.player(.pitch), .position):
            return .number(AIMPSkinProvider.pitch.script(value: flow.host.player.pitch))
        case (.equalizer, .preamp):
            return .number(AIMPSkinProvider.preamp.script(value: flow.host.player.preamp))
        case (.equalizer, .band(let aimp)):
            guard let band = flow.host.player.eqBand(aimp: aimp, aimp5: skin.archive.format == .acs5) else { return .number(0) }
            return .number(AIMPSkinProvider.equalizerBand(band).script(value: flow.host.player.eqGains[band]))
        case (.equalizer, _):
            return .number(0)
        case (_, .margin(let side)):
            guard let side else { return .number(0) }
            if let moved = engine.state.script[name].margins[side] { return .number(moved) }
            let margins = object.element?.node.properties["PlaceInfo"]?["margins"]?
                .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? []
            return .number(margins.indices.contains(side) ? margins[side] : 0)
        case (_, .parent):
            return flow.parent(of: name).map { .object(HostObject($0, in: skin)) } ?? .none
        case (_, .name):
            return .string(name)
        // The player's state reads as AIMP's enumeration names.
        case (.player(.position), .state):
            switch flow.host.player.playState {
            case .playing: return .string("opsPlay")
            case .paused: return .string("opsPause")
            case .stopped: return .string("opsStop")
            }
        case (_, .activePage):
            return .number(Double(flow.activePage(name)))
        case (_, .visible):
            // Without a script's say, whether it shows as drawn (its `Visibility` bindings, its
            // `InitialVisible`): a toggle that flips what it reads starts from what is seen.
            if let set = engine.state.script[name].visible { return .number(set ? 1 : 0) }
            switch object.element {
            case .control(let control)?: return .number(flow.isShown(control) ? 1 : 0)
            // An item as the engine reads it: its page, its dock site and AutoHide too.
            case .item?: return .number(flow.value(name, "Visibility"))
            case nil: return .number(1)
            }
        // A control's text as it shows: Soot reads its hidden language labels so (`dbLocalOffOn`'s
        // "Off|On") to build its settings' switch captions; read as a number, they said 0.
        case (_, .displayText):
            guard case .control(let control)? = object.element else { return .string("") }
            return .string(flow.displayText(control))
        // A control's `Tag`, as the skin wrote it (Red Bias 2.0's layout switches: 0, 1, 2).
        case (_, .tag) where object.element?.node.properties["Tag"]?["value"] != nil:
            let tag = object.element?.node.properties["Tag"]?["value"] ?? ""
            return Double(tag).map { .number($0) } ?? .string(tag)
        default:
            return .number(flow.value(name, path))
        }
    }

    /// `FindObject(name).Execute`: an AIMP action asks the window for it; an event handler runs in
    /// place, on this engine (Mayak-232's left and right volume knobs run `SetSettings`, which works
    /// out the volume and balance from both). Anything else has nothing to execute.
    private func execute(_ object: HostObject) throws {
        if let action = AIMPAction(object.name) {
            engine.ask(.action(action))
        } else if let provider = object.provider, provider.kind == .eventHandler, let script = provider.script,
                  let program = engine.program(script) {
            _ = try engine.budget.nested { try engine.run(program, sender: object.name) }
        }
    }
}
