import AppKit

/// One loaded skin, running: its scripts' state, what the player shows, and the scripts and timers
/// that move between them. The window controller owns one per skin and every view showing one of
/// the skin's forms (the deck, its speakers, its playlist) draws from it and changes it, so there is
/// one state rather than a copy per window kept in step. The scripts run off the main thread
/// (`scripts`); what they change of the state comes back to it here.
@MainActor
final class AIMPSkinRuntime {
    let skin: AIMPSkin

    /// The player as the engine last reported it (`update(player:)`).
    private(set) var player: AIMPSkinPlayerSnapshot
    private var playlistMatches: AIMPSkinHostState.PlaylistMatches?

    /// What a script reads outside a frame (a click's handler, a key's counter, the load scripts):
    /// the player, with no window's feedback.
    var host: AIMPSkinHostState { host(feedback: .init()) }

    /// The skin's state and the player as bindings read them, outside a frame.
    var flow: AIMPSkinDataflow { AIMPSkinDataflow(skin: skin, host: host, state: state) }

    /// What `view`'s frame reads at `clock`: the player, with the skin's meters and the window's
    /// pointer, gauges and last frame's measurements.
    func host(drawnBy view: AIMPSkinMainView, clock: Double) -> AIMPSkinHostState {
        host(feedback: AIMPSkinFrameFeedback(clock: clock, levelL: levels.left, levelR: levels.right, spectrum: spectrum,
                                             pointer: view.pointer, hoverRects: view.hoverRects,
                                             playlistRowsShown: view.playlistRowsShown,
                                             gaugeLevels: gaugesBy[ObjectIdentifier(view)]?.levels ?? [:]))
    }

    private func host(feedback: AIMPSkinFrameFeedback) -> AIMPSkinHostState {
        AIMPSkinHostState(player: player, feedback: feedback, playlistMatches: playlistMatches)
    }

    /// The skin's own state (tab pages, counters, script variables).
    var state = AIMPSkinState() {
        didSet {
            guard state != oldValue else { return }
            if state.lists.playlistSearch != oldValue.lists.playlistSearch { matchPlaylist() }
            onStateChange?()
            // Timers, animators and lamps move every frame; only the rest can change what shows,
            // so only then does the next frame measure it again.
            if state.layoutMoved(from: oldValue) { views.forEach { $0.invalidateContent() } }
            // A page turned anywhere (another window's key, a script) may change what a window
            // needs: Kantaris-Teyp's settings window shows its main window's track-info panel.
            if state.script.objects.values(\.activePage) != oldValue.script.objects.values(\.activePage) {
                views.forEach { $0.refitPages() }
            }
            // A change a tick makes is drawn by that tick; any other runs one on the next turn.
            if !ticking { scheduleTick() }
        }
    }

    /// The latest output levels and spectrum, drawn on the next animation frame.
    var levels = (left: 0.0, right: 0.0)
    var spectrum: [Double] = []

    /// What the skin asks of the player: from a key, a control, a timer or a script.
    var onAction: ((AIMPSkinCommand) -> Void)?
    /// The state moved (the controller shows and hides the skin's windows by it).
    var onStateChange: (() -> Void)?
    /// The clock started (true) or stopped: the skin's meters are measured only while it runs.
    var onClockChange: ((Bool) -> Void)?

    /// Where the skin's scripts run: off the main thread, each job from the state the last left.
    private(set) lazy var scripts = AIMPSkinScriptScheduler(skin: skin) { [weak self] in self?.state ?? AIMPSkinState() }

    /// `player`: the player now (a new skin's scripts load against it).
    init(skin: AIMPSkin, player: AIMPSkinPlayerSnapshot) {
        self.skin = skin
        self.player = player
        matchPlaylist()
        state.script.visualMode = AIMPVisualMode.saved(skin: skin.name) ?? .spectrum
    }

    /// Steps the visualization screen (`acVisualNext`, `acVisualPrev`) and keeps the choice for the skin.
    func stepVisual(by steps: Int) {
        let mode = state.script.visualMode.stepped(by: steps)
        state.script.visualMode = mode
        mode.save(skin: skin.name)
    }

    /// What the player shows now. A changed playlist (a new build of it) chooses no row; a new
    /// track scrolls the skin's own playlist to it (`placePlayingRow`).
    func update(player new: AIMPSkinPlayerSnapshot) {
        let old = player
        guard new != old else { return }
        player = new
        let playlistMoved = new.playlist != old.playlist
        if playlistMoved { matchPlaylist() }
        var state = self.state
        if playlistMoved { state.lists.select(nil) }
        if new.playlistIndex != old.playlistIndex { followsPlayingRow = true }
        placePlayingRow(in: &state)
        self.state = state
        scheduleTick()
        updateClock()
    }

    /// How many rows the skin's playlist showed in its last frame; nil before one.
    private var playlistRows: Int?
    /// A track change (or a skin just loaded) whose playing row still has to be scrolled to: it
    /// waits for a frame to say how many rows the playlist shows.
    private var followsPlayingRow = true

    /// A window's playlist showed `rows` rows (`AIMPSkinMainView.notePlaylistRows`).
    func notePlaylistRows(_ rows: Int) {
        playlistRows = rows
        guard followsPlayingRow else { return }
        var state = self.state
        placePlayingRow(in: &state)
        self.state = state
    }

    /// Scrolls the skin's own playlist to the playing track, among the rows its quick search
    /// leaves, by the rule every family's playlist follows (`PlayingRowPlacement`): the least scroll
    /// that shows it, or under shuffle the row centred.
    private func placePlayingRow(in state: inout AIMPSkinState) {
        guard followsPlayingRow, let visible = playlistRows else { return }
        followsPlayingRow = false
        let shown = host.playlistIndices(matching: state.lists.playlistSearch)
        guard player.playlistIndex >= 0, let row = shown.firstIndex(of: player.playlistIndex) else { return }
        state.lists.playlistTop = PlayingRowPlacement(shuffle: player.shuffle)
            .firstRow(showing: row, visibleRows: visible, firstRow: state.lists.playlistTop, rowCount: shown.count)
    }

    /// The quick search's matches, worked out once per playlist and search: the window asks every
    /// frame. The stale ones go first, as `host` answers from them.
    private func matchPlaylist() {
        playlistMatches = nil
        playlistMatches = .init(search: state.lists.playlistSearch, indices: host.playlistIndices(matching: state.lists.playlistSearch))
    }

    /// The views drawing this skin's forms; the deck's (`formName` nil) gives the clock its pointer.
    private var views: [AIMPSkinMainView] { attached.compactMap(\.view) }
    private var attached: [WeakView] = []
    private struct WeakView { weak var view: AIMPSkinMainView? }

    func attach(_ view: AIMPSkinMainView) {
        attached.removeAll { $0.view == nil || $0.view === view }
        attached.append(WeakView(view: view))
        updateClock()
    }

    func detach(_ view: AIMPSkinMainView) {
        attached.removeAll { $0.view == nil || $0.view === view }
        autoHiddenBy[ObjectIdentifier(view)] = nil
        gaugesBy[ObjectIdentifier(view)] = nil
        updateClock()
    }

    /// What `AutoHide` hid in each view's form as last drawn. The skin's bindings read the items
    /// hidden in the windows on screen (`AIMPSkinState.Script.autoHidden`): a docked form's own window,
    /// closed, measures nothing.
    private var autoHiddenBy: [ObjectIdentifier: Set<String>] = [:]

    func noteAutoHidden(_ hidden: Set<String>, by view: AIMPSkinMainView) {
        autoHiddenBy[ObjectIdentifier(view)] = hidden
        let onScreen = Set(views.filter(\.isOnScreen).map(ObjectIdentifier.init))
        let union = autoHiddenBy.filter { onScreen.contains($0.key) }.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        if union != state.script.autoHidden { state.script.autoHidden = union }
    }

    /// Each view's gauges, eased frame by frame toward what it last drew.
    private var gaugesBy: [ObjectIdentifier: AIMPSkinGauges] = [:]

    /// `view` drew `gauges` at `clock`: its levels move toward them.
    func easeGauges(_ gauges: [AIMPSkinControl.ID: AIMPSkinGauges.Gauge], drawnBy view: AIMPSkinMainView, clock: Double) {
        gaugesBy[ObjectIdentifier(view), default: AIMPSkinGauges()].ease(gauges, playing: player.playState == .playing, clock: clock)
    }

    /// The skin's load scripts, once, with the actions they ask for.
    func start() { run(.load) }

    /// Stops the clock and drops the scripts' work still to land; the skin is going.
    func stop() {
        scripts.cancel()
        tickScheduled = false
        guard let clock else { return }
        clock.invalidate()
        self.clock = nil
        onClockChange?(false)
    }

    // MARK: - The clock

    /// The one clock every window of the skin runs on: 30 frames a second while playing and on
    /// screen; nothing otherwise, where a change runs a single tick instead, and a skin timer
    /// due wakes it (`wakeForTimers`).
    private var clock: Timer?
    /// The wake-up for the next skin timer due while the clock is stopped.
    private var timerWake: Timer?
    /// Set while a tick's scripts' changes are taken: the state they settle is drawn by that tick.
    private var ticking = false
    private var tickScheduled = false

    /// Starts or stops the clock as playing and being seen say: a skin sent to the tray, minimized,
    /// or covered by other windows draws nothing, runs no scripts and measures no levels.
    func updateClock() {
        let wanted = player.playState == .playing && views.contains {
            guard let window = $0.window else { return false }
            return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        }
        guard wanted != (clock != nil) else { return }
        clock?.invalidate()
        clock = nil
        timerWake?.invalidate()
        timerWake = nil
        if wanted {
            // In the common modes, so it keeps running while a button is held: AppKit tracks a held
            // mouse in its event-tracking mode, where a default-mode timer waits, and the skin's own
            // timers run here (Sony TC-RX80's REW/FF seek every 100 ms while held).
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else {
            levels = (0, 0)
            scheduleTick()
        }
        onClockChange?(wanted)
    }

    /// One tick on the next turn, however many changes ask for it before then; while the clock runs,
    /// its next tick draws them.
    func scheduleTick() {
        guard clock == nil, !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tickScheduled else { return }
                self.tick()
            }
        }
    }

    /// One frame of the skin: due timers fire, visualization handlers run, then scripts whose input
    /// moved, over what the deck shows at `clock`; when they have run (off the main thread), every
    /// window draws once. The actions the scripts ask for go out last, so what they change is drawn
    /// by the next tick, never inside this one.
    func tick(at clock: Double? = nil, woken: Bool = false) {
        tickScheduled = false
        let deck = views.first { $0.formName == nil }
        let now = clock ?? deck?.scheduler.probeClock ?? CACurrentMediaTime()
        let drawn = deck.map { host(drawnBy: $0, clock: now) } ?? host(feedback: .init(clock: now))
        scripts.run([.frame], host: drawn, coalesces: true) { [weak self] outcomes in
            guard let self, let outcome = outcomes.first else { return }
            self.ticking = true
            self.apply(outcome.changes)
            self.ticking = false
            // A window off screen (a docked form's own) draws only to measure its content. Woken
            // for a timer alone, a frame that changed nothing draws nothing.
            if !(woken && outcome.changes.isEmpty) {
                for view in self.views where view.isOnScreen || view.contentDirty { view.render(clock: now) }
            }
            self.send(outcome)
            self.wakeForTimers(after: now)
        }
    }

    /// While the clock is stopped (nothing playing), the skin's timers still run, as AIMP's do: a
    /// tick when the next one is due, at most ten a second. Soot's volume ring shows on a volume
    /// change and its 2.1-s timer hides it; stopped, it stayed.
    private func wakeForTimers(after now: Double) {
        timerWake?.invalidate()
        timerWake = nil
        guard clock == nil, let due = nextTimerDue(), views.contains(where: { $0.isOnScreen }) else { return }
        let delay = max(0.1, due - now)
        let wake = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.clock == nil else { return }
                self.timerWake = nil
                self.tick(woken: true)
            }
        }
        RunLoop.main.add(wake, forMode: .common)
        timerWake = wake
    }

    /// When the next skin timer that drives something fires (`AIMPSkinScript.Engine.fireTimers`),
    /// on the clock its last firing was read on; nil when none is running. One with no `Action`
    /// link does nothing when it fires: Kantaris-Teyp's `Forward` and `Backward`, every 100 ms,
    /// woke a stopped deck to redraw it ten times a second.
    private func nextTimerDue() -> Double? {
        let flow = self.flow
        return skin.index.timers.compactMap { name, timer -> Double? in
            guard !timer.bindings.all("Action").isEmpty else { return nil }
            let script = state.script[name]
            if script.timerEnabled == false { return nil }
            if let gate = timer.bindings["Accessibility"], flow.value(of: gate) == 0 { return nil }
            let interval = AIMPSkinScript.tickedInterval(script.timerInterval ?? timer.interval ?? 1_000)
            return (state.animation[name].timerFired ?? 0) + interval
        }.min()
    }

    /// What the scripts changed, over the state as it stands now.
    private func apply(_ changes: AIMPSkinState.Changes) {
        guard !changes.isEmpty else { return }
        var state = self.state
        changes.apply(to: &state)
        self.state = state
    }

    /// Sends what the scripts ask of the player. The first job whose budget ran out is logged: the
    /// scripts it stopped run again when their input next moves, rather than stalling anything now.
    private func send(_ outcome: AIMPSkinScript.Outcome) {
        if outcome.spentBudget, !reportedSpentBudget {
            reportedSpentBudget = true
            NSLog("AIMPSkin: '%@' scripts ran out of their per-frame budget", skin.name)
        }
        outcome.commands.forEach { onAction?($0) }
    }
    private var reportedSpentBudget = false

    /// Runs `job` as an event (with its own budget, unless inside `asOneEvent`): what it changes and
    /// asks for is taken when it lands, then `done` hears whether it did anything.
    private func run(_ job: AIMPSkinScript.Job, done: (@MainActor (Bool) -> Void)? = nil) {
        if event != nil {
            event?.append((job, done))
        } else {
            run([(job, done)])
        }
    }

    /// A job, and what hears whether it did anything.
    private typealias Asked = (job: AIMPSkinScript.Job, done: (@MainActor (Bool) -> Void)?)

    private func run(_ jobs: [Asked]) {
        guard !jobs.isEmpty else { return }
        scripts.run(jobs.map(\.job), host: host) { [weak self] outcomes in
            for (outcome, asked) in zip(outcomes, jobs) {
                self?.apply(outcome.changes)
                self?.send(outcome)
                asked.done?(outcome.didSomething)
            }
        }
    }

    /// The jobs `asOneEvent` is gathering.
    private var event: [Asked]?

    /// Runs `body` as one event: every script it runs shares one budget (a pointer move over several
    /// controls' handlers), and they go to the scripts' queue together.
    func asOneEvent(_ body: () -> Void) {
        guard event == nil else { return body() }
        event = []
        body()
        let jobs = event ?? []
        event = nil
        run(jobs)
    }

    // MARK: - Changing the state

    /// Moves a skin counter to `position` and runs what its scripts ask for.
    func setCounter(_ name: String, to position: Int) { run(.setCounter(name, to: position)) }

    /// Runs a skin event handler with `sender` as `Sender`, and the actions it asks for; `done`
    /// hears whether it did anything, once it has run.
    func runHandler(_ handler: String, sender: String, arguments: [String: Double] = [:],
                    done: (@MainActor (Bool) -> Void)? = nil) {
        run(.handle(handler, sender: sender, arguments: arguments), done: done)
    }

    /// Moves a skin counter as `step` says from its position, wrapped by its `Module`: a click on a
    /// counter key, or `notches` of the wheel.
    func stepCounter(_ name: String, by step: AIMPSkinStep, notches: Int = 1) {
        run(.stepCounter(name, by: step, notches: notches))
    }

    /// Moves a skin counter `steps` positions, stopping at its ends.
    func moveCounter(_ name: String, by steps: Int) { run(.moveCounter(name, by: steps)) }

    /// Turns a tabbed group to the page `step` gives from the current one, wrapped to its tab count.
    func turnPage(_ group: String, by step: AIMPSkinStep) {
        let flow = self.flow
        let count = flow.skin.index.groups[group]?.count ?? 0
        guard count > 0 else { return }
        let current = Double(flow.activePage(group))
        let next = step.next(from: current) ?? current
        let page = ((Int(next) % count) + count) % count
        state.script[group].activePage = page
        // A mirrored page's group turns with it (`AIMPSkinIndex.mirrors`).
        let index = flow.skin.index
        if let tab = index.groups[group]?[page], let mirror = index.mirrors[tab], let other = index.tabOf[mirror] {
            state.script[other.group].activePage = other.index
        }
    }

    /// Shows a hidden item, or hides a shown one.
    func toggle(_ item: String) {
        state.script[item].visible = flow.value(item, "Visibility") == 0
    }
}

/// One window's gauges, eased toward their values at the skin's reaction speeds, per thirtieth of a
/// second gone by; while not playing they show their values as they are.
struct AIMPSkinGauges {
    /// A gauge's value in a frame and how fast it may rise and fall toward it, in its units per
    /// thirtieth of a second (`AIMPSkinFrame.gauges`).
    typealias Gauge = (value: Double, up: Double, down: Double)

    private(set) var levels: [AIMPSkinControl.ID: Double] = [:]
    /// The clock they were last eased at.
    private var clock: Double?

    mutating func ease(_ gauges: [AIMPSkinControl.ID: Gauge], playing: Bool, clock: Double) {
        defer { self.clock = clock }
        guard playing, !gauges.isEmpty else { return levels = [:] }
        let steps = min(10, max(0, (clock - (self.clock ?? clock)) * 30))
        var eased: [AIMPSkinControl.ID: Double] = [:]
        for (id, gauge) in gauges {
            let level = levels[id] ?? gauge.value
            eased[id] = level + min(gauge.up * steps, max(-gauge.down * steps, gauge.value - level))
        }
        levels = eased
    }
}
