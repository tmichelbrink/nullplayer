import AppKit

/// Where and when a skin's scripts run. Skin scripts are untrusted input: a window runs them off the
/// main thread, on the AIMP queue its frames draw on (`AIMPSkinFrameScheduler.queue`), over a copy
/// of the skin's state and a snapshot of the player, and hands the main actor back only what each
/// job changed and asked for (`AIMPSkinScript.Outcome`). The main thread never waits for them.
///
/// One request is out at a time, so each starts from the state every request before it left: those
/// asked meanwhile wait, in order, and go out together when it lands (a tick waiting gives way to a
/// later tick, as only the latest is drawn). The probe runs each request as it asks, so what it
/// clicks and counts is that request's.
@MainActor
final class AIMPSkinScriptScheduler {
    enum Timing: Equatable {
        /// On the AIMP queue; the outcome lands on a later turn of the main run loop.
        case background
        /// At once, before `run` returns (the probe).
        case inline
    }

    var timing = Timing.background

    typealias Job = AIMPSkinScript.Job
    typealias Outcome = AIMPSkinScript.Outcome

    /// Jobs that share one budget (a tick, the load, one pointer move over several handlers), the
    /// player as they were asked, and what takes their outcomes, one per job, on the main actor.
    private struct Request {
        let jobs: [Job]
        let host: AIMPSkinHostState
        let coalesces: Bool
        let done: @MainActor ([Outcome]) -> Void
    }

    private let skin: AIMPSkin
    /// The skin's state as it stands: a request starts from it when it goes out.
    private let state: @MainActor () -> AIMPSkinState
    private var running = false
    private var waiting: [Request] = []
    /// Moves on `cancel`, so an outcome of a request sent before it is dropped.
    private var generation = 0

    init(skin: AIMPSkin, state: @escaping @MainActor () -> AIMPSkinState) {
        self.skin = skin
        self.state = state
    }

    /// Runs `jobs` over `host` and hands their outcomes to `done`. `coalesces`: a request that
    /// stands for the latest of its kind (a tick), replacing one of its kind still waiting.
    func run(_ jobs: [Job], host: AIMPSkinHostState, coalesces: Bool = false, done: @escaping @MainActor ([Outcome]) -> Void) {
        guard timing == .background else {
            return done(AIMPSkinScript.perform(jobs, skin: skin, host: host, state: state()).outcomes)
        }
        if coalesces { waiting.removeAll(where: \.coalesces) }
        waiting.append(Request(jobs: jobs, host: host, coalesces: coalesces, done: done))
        if !running { send() }
    }

    /// Drops what is waiting and what is out: the skin is going.
    func cancel() {
        waiting = []
        generation += 1
    }

    /// Sends what is waiting as one hop to the AIMP queue, each request from the state the one
    /// before it left there.
    private func send() {
        guard !waiting.isEmpty else { return }
        let requests = waiting
        waiting = []
        running = true
        let skin = skin, start = state(), sent = generation
        let asked = requests.map { (jobs: $0.jobs, host: $0.host) }
        AIMPSkinFrameScheduler.queue.async { [weak self] in
            var state = start
            let outcomes = asked.map { request in
                let performed = AIMPSkinScript.perform(request.jobs, skin: skin, host: request.host, state: state)
                state = performed.state
                return performed.outcomes
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Still running while the outcomes land: a request one of them asks for waits
                    // until they all have, and starts from the state they leave.
                    if sent == self.generation {
                        for (request, outcome) in zip(requests, outcomes) { request.done(outcome) }
                    }
                    self.running = false
                    self.send()
                }
            }
        }
    }
}
