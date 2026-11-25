import Foundation

extension AIMPSkinScript {
    /// What the window asks of the skin's scripts: a frame, the load, or an event. A job carries
    /// what it was asked with, never a reading of the state: a counter key steps from wherever the
    /// counter stands when the job runs, after every job asked before it.
    enum Job: Sendable, Equatable {
        /// The scripts the skin runs as it is shown (`Engine.loaded`).
        case load
        /// One tick: timers, visualization handlers, animators, then the scripts whose input moved
        /// (`Engine.frame`).
        case frame
        /// A counter moved to a position (`Engine.setCounter`).
        case setCounter(String, to: Int)
        /// A counter key pressed, or the wheel over it: `step`'s next position from where it stands,
        /// `notches` times, wrapped by the counter's `Module`.
        case stepCounter(String, by: AIMPSkinStep, notches: Int)
        /// A counter moved `by` positions, stopping at its ends (the wheel over a knob that turns one).
        case moveCounter(String, by: Int)
        /// An event handler run for a control (`Engine.handle`).
        case handle(String, sender: String, arguments: [String: Double])
    }

    /// What one job did: what it changed of the skin's state, and what it asks of the player, in order.
    struct Outcome: Sendable {
        let changes: AIMPSkinState.Changes
        let commands: [AIMPSkinCommand]
        /// The budget the job ran on had run out by its end (it, or one before it on that budget,
        /// stopped short).
        let spentBudget: Bool

        /// Whether the job changed anything or asked for anything (a press the skin's handler
        /// ignores moves the window instead).
        var didSomething: Bool { !changes.isEmpty || !commands.isEmpty }
    }

    /// Runs `jobs` in order on one budget, each on a fresh engine over the state the one before it
    /// left; returns what each did and the state they leave. Pure: it reads only what it is given,
    /// so it runs on any thread (the window runs it on the AIMP queue, `AIMPSkinScriptScheduler`).
    static func perform(_ jobs: [Job], skin: AIMPSkin, host: AIMPSkinHostState,
                        state: AIMPSkinState) -> (outcomes: [Outcome], state: AIMPSkinState) {
        let budget = Budget()
        var state = state
        let outcomes = jobs.map { job in
            let engine = Engine(skin: skin, host: host, state: state, budget: budget)
            engine.perform(job)
            defer { state = engine.state }
            return Outcome(changes: AIMPSkinState.Changes(from: state, to: engine.state), commands: engine.actions,
                           spentBudget: budget.isSpent)
        }
        return (outcomes, state)
    }
}

extension AIMPSkinScript.Engine {
    func perform(_ job: AIMPSkinScript.Job) {
        switch job {
        case .load:
            loaded()
        case .frame:
            frame()
        case .setCounter(let name, let position):
            setCounter(name, to: position)
        case .stepCounter(let name, let step, let notches):
            let flow = self.flow
            let current = flow.value(name, "Position")
            let next = step.next(from: current, notches: notches) ?? current
            setCounter(name, to: flow.wrapped(AIMPSkinScript.integer(next), counter: name))
        case .moveCounter(let name, let steps):
            guard let module = skin.index.counterModule(name) else { return }
            // Saturating: a script can leave the counter anywhere, `Int.max` included.
            let moved = AIMPSkinScript.integer(flow.value(name, "Position")).addingReportingOverflow(steps)
            let position = moved.overflow ? (steps > 0 ? Int.max : Int.min) : moved.partialValue
            setCounter(name, to: min(max(position, 0), module - 1))
        case .handle(let handler, let sender, let arguments):
            handle(handler, sender: sender, arguments: arguments)
        }
    }
}
