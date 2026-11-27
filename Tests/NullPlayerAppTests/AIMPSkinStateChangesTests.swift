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
        carried(AIMPSkinState(), after)
        carried(after, AIMPSkinState())
    }
}
