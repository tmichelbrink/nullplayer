import XCTest
@testable import NullPlayer

/// `AIMPSkinState.Changes` carries every part of the state a script job changes back to the window:
/// a part its field list leaves out would be lost between the AIMP queue and the window. Each test
/// sets every part, and counts the parts, so one added later without a field fails here.
final class AIMPSkinStateChangesTests: XCTestCase {
    private func carried(_ before: AIMPSkinState, _ after: AIMPSkinState, file: StaticString = #filePath, line: UInt = #line) {
        var applied = before
        AIMPSkinState.Changes(from: before, to: after).apply(to: &applied)
        XCTAssertEqual(applied, after, file: file, line: line)
    }

    func testEveryPartOfAnObjectIsCarried() {
        var object = AIMPSkinState.Object()
        object.activePage = 2
        object.counter = 3
        object.visible = false
        object.autoHidden = true
        object.scrollTop = 12
        object.properties = ["Resources.BackgroundColor": "1"]
        object.expression = "%T"
        object.docked = true
        object.parent = "Holder"
        object.timerEnabled = false
        object.timerInterval = 250
        object.timerGate = 1
        object.visibleGate = 0
        object.margins = [1: 4]
        object.text = "Text"
        XCTAssertEqual(Mirror(reflecting: object).children.count, 15, "a part added to Object needs setting here, and a field in Changes")

        var after = AIMPSkinState()
        after.script["Knob"] = object
        carried(AIMPSkinState(), after)
        carried(after, AIMPSkinState())

        // The same record with every part changed: each field is carried over the one before.
        var changed = object
        changed.activePage = 5
        changed.counter = 6
        changed.visible = true
        changed.autoHidden = false
        changed.scrollTop = 20
        changed.properties = ["Resources.BackgroundColor": "2"]
        changed.expression = "%A"
        changed.docked = false
        changed.parent = "Other"
        changed.timerEnabled = true
        changed.timerInterval = 500
        changed.timerGate = 0
        changed.visibleGate = 1
        changed.margins = [1: 8]
        changed.text = "Changed"
        var updated = AIMPSkinState()
        updated.script["Knob"] = changed
        carried(after, updated)
    }

    func testEveryPartOfAMotionIsCarried() {
        var motion = AIMPSkinState.Motion()
        motion.timerFired = 1
        motion.scriptInputs = [0.5]
        motion.frame = 3
        motion.stepped = 2
        motion.opacity = 128
        XCTAssertEqual(Mirror(reflecting: motion).children.count, 5, "a part added to Motion needs setting here, and a field in Changes")

        var after = AIMPSkinState()
        after.animation["Lamp"] = motion
        carried(AIMPSkinState(), after)
        carried(after, AIMPSkinState())

        var changed = motion
        changed.timerFired = 2
        changed.scriptInputs = [0.25]
        changed.frame = 4
        changed.stepped = 3
        changed.opacity = 64
        var updated = AIMPSkinState()
        updated.animation["Lamp"] = changed
        carried(after, updated)
    }

    func testTheScriptsStoresAndTheListsAreCarried() {
        var after = AIMPSkinState()
        after.script.resourceLinks = ["Skin.Face_": "Skin.Face_7"]
        after.script.config = ["Theme": "Dark"]
        after.script.variables = ["g_mode": "2"]
        after.script.visualMode = .scope
        after.lists.playlistTop = 4
        after.lists.playlistSearch = "word"
        XCTAssertEqual(Mirror(reflecting: after.script).children.count, 5, "a part added to Script needs setting here, and a field in Changes")
        XCTAssertEqual(Mirror(reflecting: after).children.count, 3, "a part added to the state needs setting here, and a field in Changes")
        XCTAssertEqual(Mirror(reflecting: AIMPSkinState.Animation()).children.count, 1, "a part added to Animation needs a field in Changes")
        carried(AIMPSkinState(), after)
        carried(after, AIMPSkinState())
    }
}
