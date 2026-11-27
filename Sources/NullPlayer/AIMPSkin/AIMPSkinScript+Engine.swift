import Foundation

extension AIMPSkinScript {
    /// One job's script work (a tick's, the load's, an event's): the skin, what the player shows, the skin's state as
    /// the scripts leave it, and what they asked of the player, in order. Every script the tick or
    /// event runs, nested ones included (a counter a script moves, a handler it executes), runs on
    /// this one engine and its budget: there is nothing to merge back.
    ///
    /// A run that stops (an unsupported call, the budget spent) leaves nothing behind: what it set
    /// and asked for is undone, and its caller goes on (`atomically`).
    ///
    /// Of no actor: an engine lives on the thread that made it, for one job (`perform(_:)`), and
    /// reads only the values it was given. The window runs it on the AIMP queue, off the main
    /// thread (`AIMPSkinScriptScheduler`); the main actor gets back what it changed and asked for.
    final class Engine {
        let skin: AIMPSkin
        let host: AIMPSkinHostState
        /// Set by the scripts as they run (`AIMPSkinScript.Run` and its host bridge).
        var state: AIMPSkinState
        private(set) var actions: [AIMPSkinCommand] = []
        let budget: Budget
        /// Scripted counters whose scripts are running: one that sets itself only moves.
        private var runningCounters: Set<String> = []
        /// What the scripts wrote to AIMP's EQ bands, in dB, by the NullPlayer band each lands on:
        /// AIMP bands that share one are averaged (`AIMPSkinCommand.equalizerBand`).
        private var eqWrites: [Int: [Int: Double]] = [:]

        init(skin: AIMPSkin, host: AIMPSkinHostState, state: AIMPSkinState, budget: Budget = Budget()) {
            self.skin = skin
            self.host = host
            self.state = state
            self.budget = budget
        }

        /// The dataflow over the state as it stands, so a value a script set reads back as set.
        var flow: AIMPSkinDataflow { AIMPSkinDataflow(skin: skin, host: host, state: state) }

        /// A script by name: compiled as the skin loaded (`AIMPSkinScript.Library`).
        func program(_ name: String) -> Program? { skin.scripts.programs[name.lowercased()] }

        // MARK: - What a tick or an event runs

        /// Runs, once, as the skin is shown: each script named after a form, as AIMP runs it when it
        /// makes the form (GX-77 4K's `AIMPMainForm` hides its position preview and zeroes its
        /// counters), the main form's first; then the main form's `OnLoaded` handler (Nakamichi BX's
        /// switches its seek timers off; left running, they wound forward ten times a second).
        func loaded() {
            for form in ["AIMPMainForm"] + skin.companions.map(\.name) where program(form) != nil {
                handle(form, sender: form)
            }
            if let onLoaded = skin.index.onLoaded {
                handle(onLoaded, sender: "AIMPMainForm")
            }
        }

        /// One frame, as the window runs it: due timers fire, visualization handlers run and
        /// animators step, then the scripts whose input moved.
        func frame() {
            fireTimers()
            visualize()
            settle()
        }

        /// Fires every `LogicalOperatorTimer` whose `Interval` has passed since it last fired, on
        /// `host.feedback.clock`, while its `Accessibility` binding is on (or it has none): each `Action`
        /// link sets its source counter to the link's `Expression` of its position, running the
        /// counter's script (Pioneer CT-F1000's tape counter turns this way).
        func fireTimers() {
            for (name, timer) in skin.index.timers {
                // A timer's `Accessibility` binding pushes its value whenever it changes, taking the
                // timer back from a script that switched it off: Sony TC-RX80 switches its REW/FF
                // timers off when it loads, and its REW/FF keys' counter turns them on through the
                // binding alone.
                if let gate = timer.bindings["Accessibility"] {
                    let value = flow.value(of: gate)
                    if let last = state.script[name].timerGate, last != value { state.script[name].timerEnabled = nil }
                    state.script[name].timerGate = value
                }
                // Nakamichi BX switches its seek timers off when it loads and on while winding.
                if state.script[name].timerEnabled == false { continue }
                // On Windows' 15.6 ms timer ticks, as the skin's author saw it.
                let interval = tickedInterval(state.script[name].timerInterval ?? timer.interval ?? 1_000)
                let last = state.animation[name].timerFired ?? -.infinity
                guard host.feedback.clock - last >= interval else { continue }
                // Every link reads the counters as the timer fired; a tick its gate holds back does
                // not fire, so the interval still runs from the last one that did.
                let flow = self.flow
                if let gate = timer.bindings["Accessibility"], flow.value(of: gate) == 0 { continue }
                state.animation[name].timerFired = host.feedback.clock
                for link in timer.bindings.all("Action") {
                    guard let source = link.source else { continue }
                    // A timer on an action repeats it (Technics' REW/FF held down seek every 100 ms).
                    if let action = AIMPAction(source) {
                        actions.append(.action(action))
                        continue
                    }
                    setCounter(source, to: flow.wrapped(AIMPSkinScript.integer(flow.value(of: link)), counter: source))
                }
            }
        }

        /// Runs each `ScriptableVisualizationHandler` on the spectrum, as AIMP does every visual
        /// frame, then steps the animators that keep their own frame: a speaker's handler kicks a
        /// cone back to frame 0 on a beat, and the cone plays to where its own gate stops it. A
        /// handler only animates: what it asks of the player is dropped.
        func visualize() {
            if host.player.playState == .playing, !host.feedback.spectrum.isEmpty {
                droppingRequests {
                    for (_, provider) in skin.index.visualizationHandlers {
                        guard let script = provider.script, let program = program(script) else { continue }
                        do {
                            try atomically { _ = try run(program) }
                        } catch {
                            if AIMPSkinTrace.items || AIMPSkinTrace.visualize { print("  VISUAL_FAIL \(script) \(error)") }
                        }
                    }
                }
            }
            stepAnimators()
        }

        /// Runs every script whose bound input changed, until nothing changes (a few passes at most).
        /// The first run of each, as a skin loads, only sets its state up: what it asks of the
        /// player is dropped (the GX-F90's EQ scripts would otherwise rewrite the EQ).
        func settle() {
            pushVisibility()
            for _ in 0..<4 {
                // A pass reads every input as it began.
                let flow = self.flow
                let providers = skin.index.providers.sorted { $0.key < $1.key }
                var changed = false
                for (name, provider) in providers where provider.kind == .counter(scripted: true) {
                    guard let script = provider.script else { continue }
                    // One bound to nothing runs once as the skin loads, on where it stands, so what it
                    // sets up holds from the start (M5's layout script docks its library and playlist):
                    // run only on a click, its windows stood empty until the layout was changed. A
                    // command a key fires runs on the press alone (`AIMPSkinIndex.commandCounters`).
                    guard let link = provider.bindings["Position"] else {
                        guard state.animation[name].scriptInputs == nil, !budget.isSpent,
                              !skin.index.commandCounters.contains(name) else { continue }
                        let position = Double(state.script[name].counter ?? provider.positionDefault)
                        state.animation[name].scriptInputs = [position]
                        changed = true
                        guard let program = program(script) else { continue }
                        // Out of budget, it has not run: it runs on a later tick, as a bound one does.
                        droppingRequests {
                            if stopsOnLimit({ try runCounter(name, program, at: position) }) {
                                state.animation[name].scriptInputs = nil
                            }
                        }
                        continue
                    }
                    let inputs = flow.inputs(of: link)
                    let previous = state.animation[name].scriptInputs
                    guard previous != inputs else { continue }
                    // Out of budget, the input stays unseen, so its script runs on a later tick.
                    guard !budget.isSpent else { break }
                    state.animation[name].scriptInputs = inputs
                    changed = true
                    guard let program = program(script) else { continue }
                    droppingRequests(if: previous == nil) {
                        if stopsOnLimit({ try runCounter(name, program, at: flow.value(of: link)) }) {
                            state.animation[name].scriptInputs = previous
                        }
                    }
                }
                // Event handlers bound to a value run when it moves: `prvPlayerState`'s `OnTrackStarted`
                // and `OnTrackFinished` (a count the host keeps), or a provider (Mayak-232's
                // `SetSliderTrigger`, the volume and balance: its knobs follow them).
                for (name, provider) in providers where provider.kind == .eventHandler {
                    guard let link = provider.bindings["Handler"] else { continue }
                    let input = flow.inputs(of: link)
                    let previous = state.animation[name].scriptInputs
                    guard previous != input else { continue }
                    guard !budget.isSpent else { break }
                    state.animation[name].scriptInputs = input
                    changed = true
                    // As the skin loads, a value trigger sets it up from where things stand; of the events
                    // (`On…`, and a provider's `Action`: the user moved it), only a track start has
                    // happened, if something is playing (SL-1200 drops its arm and wipes the cover art in;
                    // Soot's volume ring waits for the volume to move).
                    if previous == nil, let event = link.pin, event.hasPrefix("On") || event == "Action",
                       event != "OnTrackStarted" || host.player.playState != .playing { continue }
                    droppingRequests(if: previous == nil) {
                        if handle(name, sender: name) { state.animation[name].scriptInputs = previous }
                    }
                }
                if !changed { break }
            }
        }

        /// A control or item a script showed or hid (`Set('Visible', …)`) goes back to its
        /// `Visibility` bindings when their value changes, as AIMP's bindings push theirs: Vega
        /// MP-120's script swaps its stop key for an inert one when it stops, and playback started
        /// another way (its next key) left the inert one shown, so stop did nothing.
        private func pushVisibility() {
            let flow = self.flow
            for name in state.script.objects.values(\.visible).keys {
                guard let value = flow.visibilityGate(name) else { continue }
                if let last = state.script[name].visibleGate, last != value { state.script[name].visible = nil }
                state.script[name].visibleGate = value
            }
        }

        /// Sets counter `name` to `value`. A `ScriptableOperatorCounter` runs its script with `State`
        /// the new value (Pioneer's play key sets `RemoteControllScript` to 1, and the script
        /// plays), and `State` after the run is the counter's position. Stopped by a limit (the step
        /// budget, the text length), the counter stays where it was, so its script runs on the next move.
        func setCounter(_ name: String, to value: Int) {
            _ = stopsOnLimit { try movingCounter(name, to: value) }
        }

        /// As `setCounter`, for a script that moves a counter: stopped by a limit, the counter is put
        /// back and the limit passed on, so the script that moved it is undone too and both run again
        /// on a later tick (rather than the outer one standing, its input seen, and the move lost).
        /// Any other failure stays the counter script's.
        func movingCounter(_ name: String, to value: Int) throws {
            let before = state
            let turned = flow.value(name, "Position") != Double(value)
            state.script[name].counter = value
            // The windows it shows and hides follow it as it turns (`AIMPSkinIndex.windowCounters`).
            if turned {
                for each in skin.index.windowCounters[name] ?? [] {
                    state.override(visible: each.link.shaped(Double(value)) != 0, of: each.form, gateFrom: flow)
                }
            }
            guard let provider = skin.index.providers[name], provider.kind == .counter(scripted: true),
                  let script = provider.script, let program = program(script) else { return }
            do {
                try runCounter(name, program, at: Double(value))
            } catch let spent as Budget.Spent {
                state = before
                throw spent
            } catch {
                // A script error in the counter's script ends that script where it was raised, as
                // `setCounter` always has; it is not the moving script's to stop on.
            }
        }

        /// Runs the event handler `handler` (a `ScriptableEventHandler` provider, or a script by
        /// name) for `sender`, with a mouse event's `arguments`. True when a limit stopped it (and
        /// what it did was undone).
        @discardableResult
        func handle(_ handler: String, sender: String, arguments: [String: Double] = [:]) -> Bool {
            guard let program = program(skin.index.providers[handler]?.script ?? handler) else { return false }
            return stopsOnLimit { try atomically { _ = try run(program, sender: sender, arguments: arguments) } }
        }

        /// Whether `body` stopped on a limit: the step budget, the call depth or the text length,
        /// each a `Budget.Spent`, whether or not the tick's step budget is spent. Any other failure
        /// (a script error) is not retried.
        private func stopsOnLimit(_ body: () throws -> Void) -> Bool {
            do { try body(); return false } catch is Budget.Spent { return true } catch { return false }
        }

        // MARK: - Running

        /// Counter `name`'s script on `position`, guarded against the counter's own moves while it
        /// runs; its `State` after is the counter's position.
        private func runCounter(_ name: String, _ program: Program, at position: Double) throws {
            guard !runningCounters.contains(name) else { return }
            runningCounters.insert(name)
            defer { runningCounters.remove(name) }
            // One call deeper on the budget, its block too: counters whose blocks move each other
            // stop at the depth limit rather than running the stack out.
            let after = try budget.nested { try atomically { try run(program, statePosition: position) } }
            state.script[name].counter = AIMPSkinScript.integer(after)
        }

        /// `program` once: its block, then `Execute` with the event's parameters (`State` at
        /// `statePosition`, `Sender`, `Arguments`). Returns `State` after the run. A nested run (a
        /// handler a script executes) is one call deeper on the budget.
        @discardableResult
        func run(_ program: Program, sender: String = "", arguments: [String: Double] = [:],
                 statePosition: Double = 0) throws -> Double {
            try Run(engine: self, program: program, sender: sender, arguments: arguments).execute(statePosition: statePosition)
        }

        /// `body`, what it asks of the player dropped when `drop` holds (a run that only sets the
        /// skin up, as it loads, or a visualization handler, which only animates).
        private func droppingRequests(if drop: Bool = true, _ body: () -> Void) {
            let asked = (actions, eqWrites)
            body()
            if drop { (actions, eqWrites) = asked }
        }

        /// `body`, all or nothing: when it throws, what it set and asked for is undone.
        private func atomically<T>(_ body: () throws -> T) throws -> T {
            let saved = (state, actions, eqWrites)
            do {
                return try body()
            } catch {
                (state, actions, eqWrites) = saved
                throw error
            }
        }

        // MARK: - What the scripts ask of the player

        func ask(_ command: AIMPSkinCommand) { actions.append(command) }

        /// AIMP's preamp, 0–1: the latest a script set is the one asked for.
        func setPreamp(_ value: Double) {
            replace(.preamp, with: value)
        }

        /// AIMP's EQ band `aimp`, 0–1, on NullPlayer band `band`: the band is asked for once, at the
        /// mean of the AIMP bands written to it.
        func setEqualizer(band: Int, aimp: Int, to value: Double) {
            eqWrites[band, default: [:]][aimp] = value
            let values = eqWrites[band]?.values.map { $0 } ?? []
            replace(.equalizerBand(band), with: values.reduce(0, +) / Double(values.count))
        }

        /// Asks for `provider` at `value` in place of what was asked of it before.
        private func replace(_ provider: AIMPSkinProvider, with value: Double) {
            actions.removeAll { if case .set(provider, _) = $0 { true } else { false } }
            actions.append(.set(provider, value))
        }

        // MARK: - Animators

        /// Animators that gate on their own frame, or that a script set, advance on their interval
        /// while their gate is open (a cone runs from 0 until `Value < 3` closes it).
        private func stepAnimators() {
            let flow = self.flow
            for animator in skin.index.animatorList {
                guard let name = animator.name else { continue }
                let bindings = animator.bindings
                guard state.animation[name].frame != nil || bindings.links.contains(where: { $0.source == name }) else { continue }
                // One bound to a counter is on the counter's position, and its steps move the counter
                // (Technics SL-1200's tonearm: `Frames_Counter` drops it in, then a script sets it).
                let counter = bindings.all("AnimationFrameIndex").first { $0.expression == nil }
                    .flatMap(\.source).flatMap { skin.index.counterModule($0) != nil ? $0 : nil }
                let frame = counter.map { AIMPSkinScript.integer(flow.value($0, "Position")) } ?? state.animation[name].frame ?? 0
                state.animation[name].frame = frame
                // A frame a script set outside a frame (a click's handler, which has no clock) waits
                // its interval from this frame (`HostBridge`'s `FrameIndex`), not from clock 0.
                if state.animation[name].stepped == .infinity { state.animation[name].stepped = host.feedback.clock }
                // A gate on its own frame reads the frame it is on now.
                if let gate = bindings["Accessibility"] {
                    let open = gate.source == name ? gate.shaped(Double(frame)) : flow.value(of: gate)
                    if open == 0 { continue }
                }
                let frames = max(1, skin.image(animator.picture, links: state.script.resourceLinks)?.frameCount ?? 1)
                guard let asked = animator.animator?.interval,
                      host.feedback.clock - (state.animation[name].stepped ?? 0) >= tickedInterval(max(1, asked)) else { continue }
                state.animation[name].stepped = host.feedback.clock
                // Reduced first, so a script's `Int.max` or negative frame wraps rather than traps.
                let next = ((frame % frames + frames) % frames + 1) % frames
                state.animation[name].frame = next
                if let counter { state.script[counter].counter = next }
            }
        }
    }
}
