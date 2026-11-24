import Foundation
import XCTest
@testable import NullPlayer

/// Skin scripts run off the main thread: on the AIMP queue, over a copy of the state, handing the
/// main actor back what each job changed and asked for. Synthetic scripts on a skin built in memory.
@MainActor
final class AIMPSkinScriptSchedulerTests: XCTestCase {
    /// `Seen := Seen + 1`, then asks the player to play.
    private static let bump = """
    <program><procedure><name text="Execute"/><compoundstmt>
      <assignstmt><dsgn><node text="Seen"/></dsgn><expr><dsgn><node text="Seen"/></dsgn><op text="+"/><number text="1"/></expr></assignstmt>
      <callstmt><dsgn><node text="FindObject"/><expr><string text="'acPlayerPlay'"/></expr><node text="Execute"/></dsgn></callstmt>
    </compoundstmt></procedure></program>
    """
    /// Sets `Seen`, then loops for ever.
    private static let runaway = """
    <program><procedure><name text="Execute"/><compoundstmt>
      <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="7"/></expr></assignstmt>
      <whilestmt><expr><number text="1"/></expr><compoundstmt/></whilestmt>
    </compoundstmt></procedure></program>
    """

    private static func skin() throws -> AIMPSkin {
        try AIMPSkinScriptTests.skin(scripts: ["Bump": bump, "Runaway": runaway])
    }

    /// With the AIMP queue held, a handler asked for does not run: the main thread goes on, and
    /// nothing has changed. Let go, the jobs land in order, each on what the one before left, as
    /// changes to the state and commands for the player; a change made on main meanwhile stays.
    func testScriptsRunOnTheAIMPQueueAndLandAsChangesAndCommands() throws {
        let runtime = AIMPSkinRuntime(skin: try Self.skin(), player: .probe)
        var asked: [AIMPSkinCommand] = []
        runtime.onAction = { asked.append($0) }
        var answered: Bool?

        AIMPSkinFrameScheduler.queue.suspend()
        runtime.runHandler("Bump", sender: "Key") { answered = $0 }
        runtime.runHandler("Bump", sender: "Key")
        runtime.state.lists.playlistTop = 3
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let heldVariables = runtime.state.script.variables, heldAsked = asked, heldAnswer = answered
        AIMPSkinFrameScheduler.queue.resume()

        XCTAssertEqual(heldVariables, [:], "nothing ran while the queue was held")
        XCTAssertEqual(heldAsked, [])
        XCTAssertNil(heldAnswer)
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in asked.count == 2 }, object: nil)
        wait(for: [landed], timeout: 5)
        XCTAssertEqual(answered, true)
        XCTAssertEqual(asked, [.action(.playerPlay), .action(.playerPlay)])
        XCTAssertEqual(runtime.state.script.variables["seen"], "2", "the second ran on what the first left")
        XCTAssertEqual(runtime.state.lists.playlistTop, 3, "the change made on main while they ran stays")
    }

    /// A runaway script spends its budget on the AIMP queue, not the main thread: with that queue
    /// held, asking for it returns at once with nothing run; let go, it lands as nothing done, its
    /// writes undone. (Held rather than timed, so a busy machine cannot fail it.)
    func testARunawayScriptCannotStallTheMainThread() throws {
        let skin = try Self.skin()
        let runaway = AIMPSkinScript.Job.handle("Runaway", sender: "Key", arguments: [:])
        let inline = AIMPSkinScript.perform([runaway], skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
        XCTAssertEqual(inline.outcomes.first?.spentBudget, true)

        let runtime = AIMPSkinRuntime(skin: skin, player: .probe)
        var asked: [AIMPSkinCommand] = []
        runtime.onAction = { asked.append($0) }
        var answered: Bool?
        AIMPSkinFrameScheduler.queue.suspend()
        runtime.runHandler("Runaway", sender: "Key") { answered = $0 }
        let heldAnswer = answered, heldVariables = runtime.state.script.variables
        AIMPSkinFrameScheduler.queue.resume()
        XCTAssertNil(heldAnswer, "main returned before the script ran")
        XCTAssertEqual(heldVariables, [:])

        let landed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in answered != nil }, object: nil)
        wait(for: [landed], timeout: 5)
        XCTAssertEqual(answered, false, "stopped by its budget, it did nothing")
        XCTAssertEqual(asked, [])
        XCTAssertNil(runtime.state.script.variables["seen"], "what it set before the loop is undone")
    }

    /// Requests made while one is out wait, in order, and go out together; of the ticks waiting
    /// only the latest runs. A cancelled scheduler lands nothing.
    func testWaitingTicksGiveWayToTheLatestAndEventsKeepTheirOrder() throws {
        var state = AIMPSkinState()
        let scheduler = AIMPSkinScriptScheduler(skin: try Self.skin()) { state }
        let host = AIMPSkinHostState(player: .probe)
        var landed: [String] = []

        AIMPSkinFrameScheduler.queue.suspend()
        scheduler.run([.frame], host: host, coalesces: true) { _ in landed.append("tick 1") }
        scheduler.run([.frame], host: host, coalesces: true) { _ in landed.append("tick 2") }
        scheduler.run([.handle("Bump", sender: "Key", arguments: [:])], host: host) { outcomes in
            landed.append("bump")
            outcomes.first?.changes.apply(to: &state)
        }
        scheduler.run([.frame], host: host, coalesces: true) { _ in landed.append("tick 3") }
        AIMPSkinFrameScheduler.queue.resume()

        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in landed.count == 3 }, object: nil)
        wait(for: [done], timeout: 5)
        // Drained: a marker behind any further request on the AIMP queue, then behind its outcome on
        // the main queue, so a fourth landing would be seen.
        let settled = expectation(description: "drained")
        AIMPSkinFrameScheduler.queue.async { DispatchQueue.main.async { settled.fulfill() } }
        wait(for: [settled], timeout: 5)
        XCTAssertEqual(landed, ["tick 1", "bump", "tick 3"])
        XCTAssertEqual(state.script.variables["seen"], "1")

        AIMPSkinFrameScheduler.queue.suspend()
        scheduler.run([.handle("Bump", sender: "Key", arguments: [:])], host: host) { _ in landed.append("cancelled") }
        scheduler.cancel()
        // A marker behind the cancelled request on the AIMP queue, then behind its outcome on the
        // main queue: once it lands, the outcome has had its chance to.
        let drained = expectation(description: "the cancelled request's outcome had its chance to land")
        AIMPSkinFrameScheduler.queue.async { DispatchQueue.main.async { drained.fulfill() } }
        AIMPSkinFrameScheduler.queue.resume()
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(landed.count, 3, "a cancelled request's outcome is dropped")
    }

    /// The probe runs each request as it asks: the outcome lands before `run` returns.
    func testTheProbeRunsScriptsAsItAsks() throws {
        let runtime = AIMPSkinRuntime(skin: try Self.skin(), player: .probe)
        runtime.scripts.timing = .inline
        var asked: [AIMPSkinCommand] = []
        runtime.onAction = { asked.append($0) }
        runtime.asOneEvent {
            runtime.runHandler("Bump", sender: "Key")
            runtime.runHandler("Bump", sender: "Key")
        }
        XCTAssertEqual(asked, [.action(.playerPlay), .action(.playerPlay)])
        XCTAssertEqual(runtime.state.script.variables["seen"], "2")
    }

    // MARK: - Changes

    /// Every part of the state a job changes comes back in its changes. A part added to the state
    /// must be added to `AIMPSkinState.Changes.fields` and set here.
    func testChangesCarryEveryPartOfTheState() {
        let message = "a new part of the state needs a field in Changes"
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState()).children.count, 3, message)
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState.Script()).children.count, 5, message)
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState.Object()).children.count, 15, message)
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState.Animation()).children.count, 1, message)
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState.Motion()).children.count, 5, message)

        let before = AIMPSkinState()
        var after = before
        after.script["Tabs"].activePage = 1
        after.script["Counter"].counter = 2
        after.script["Item"].visible = false
        after.script["Hidden"].autoHidden = true
        after.script["Item"].properties = ["Font.Color": "1"]
        after.script["Text"].expression = "%T"
        after.script["Form"].docked = true
        after.script["Item"].parent = "Host"
        after.script["Timer"].timerEnabled = false
        after.script["Timer"].timerInterval = 50
        after.script["Timer"].timerGate = 1
        after.script["Item"].margins = [0: 4]
        after.script["Display"].text = "Text"
        after.script["View"].scrollTop = 120
        after.script["Key"].visibleGate = 1
        after.script.resourceLinks["Skin.Face"] = "Skin.Face2"
        after.script.config["Key"] = "Value"
        after.script.variables["seen"] = "3"
        after.script.visualMode = .vu
        after.animation["Timer"].timerFired = 10
        after.animation["Counter"].scriptInputs = [1, 2]
        after.animation["Reel"].frame = 3
        after.animation["Reel"].stepped = 11
        after.animation["Lamp"].opacity = 128
        after.lists.playlistTop = 5

        var applied = before
        AIMPSkinState.Changes(from: before, to: after).apply(to: &applied)
        XCTAssertEqual(applied, after)
        XCTAssertTrue(AIMPSkinState.Changes(from: after, to: after).isEmpty)
    }

    /// Changes go over the state as it stands: a part the job set or cleared takes the job's value;
    /// a part changed on main meanwhile, and one the job left alone, stay as main has them, on the
    /// same object too.
    func testChangesKeepWhatMainChangedMeanwhile() {
        var before = AIMPSkinState()
        for name in ["Mine", "Theirs", "Gone"] { before.script[name].counter = 1 }
        var after = before
        after.script["Mine"].counter = 2
        after.script["Gone"].counter = nil

        var now = before
        now.script["Theirs"].counter = 5
        now.script["Mine"].activePage = 2
        now.lists.playlistTop = 7
        AIMPSkinState.Changes(from: before, to: after).apply(to: &now)
        XCTAssertEqual(now.script.objects.values(\.counter), ["Mine": 2, "Theirs": 5])
        XCTAssertEqual(now.script.objects.values(\.activePage), ["Mine": 2])
        XCTAssertEqual(now.lists.playlistTop, 7)
    }

    /// An object with nothing left set has no record: a state that set and cleared a part is the
    /// state that never set it.
    func testAnObjectWithNothingSetHasNoRecord() {
        var state = AIMPSkinState()
        state.script["Timer"].timerEnabled = false
        state.script["Timer"].timerEnabled = nil
        XCTAssertEqual(state, AIMPSkinState())
        state.script.autoHidden = ["A", "B"]
        state.script.autoHidden = ["B"]
        XCTAssertEqual(state.script.autoHidden, ["B"])
        XCTAssertEqual(state.script.objects.byName.count, 1)
    }
}
