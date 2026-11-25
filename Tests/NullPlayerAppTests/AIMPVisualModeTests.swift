import XCTest
@testable import NullPlayer

/// The visualization screen's modes: VisNext / VisPrev step them, wrapping, and the choice is kept
/// per skin.
final class AIMPVisualModeTests: XCTestCase {
    func testStepsWrapBothWays() {
        XCTAssertEqual(AIMPVisualMode.spectrum.stepped(by: 1), .scope)
        XCTAssertEqual(AIMPVisualMode.off.stepped(by: 1), .spectrum)
        XCTAssertEqual(AIMPVisualMode.spectrum.stepped(by: -1), .off)
        XCTAssertEqual(AIMPVisualMode.vu.stepped(by: -5), .scope)
    }

    func testTheChoiceIsKeptPerSkin() throws {
        let suite = "AIMPVisualModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(AIMPVisualMode.saved(skin: "A", defaults: defaults))
        AIMPVisualMode.vu.save(skin: "A", defaults: defaults)
        XCTAssertEqual(AIMPVisualMode.saved(skin: "A", defaults: defaults), .vu)
        XCTAssertNil(AIMPVisualMode.saved(skin: "B", defaults: defaults))
    }

    func testAIMPKnowsTheStepActions() {
        XCTAssertEqual(AIMPAction("acVisualNext"), .visualNext)
        XCTAssertEqual(AIMPAction("acVisualPrev"), .visualPrev)
    }
}
