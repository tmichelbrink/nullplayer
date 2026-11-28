import XCTest
@testable import NullPlayer

/// The visualization screen's modes: VisNext / VisPrev step them, wrapping (the choice is kept per
/// skin: `AIMPSkinStoreTests`).
final class AIMPVisualModeTests: XCTestCase {
    func testStepsWrapBothWays() {
        XCTAssertEqual(AIMPVisualMode.spectrum.stepped(by: 1), .scope)
        XCTAssertEqual(AIMPVisualMode.off.stepped(by: 1), .spectrum)
        XCTAssertEqual(AIMPVisualMode.spectrum.stepped(by: -1), .off)
        XCTAssertEqual(AIMPVisualMode.vu.stepped(by: -5), .scope)
    }

    func testAIMPKnowsTheStepActions() {
        XCTAssertEqual(AIMPAction("acVisualNext"), .visualNext)
        XCTAssertEqual(AIMPAction("acVisualPrev"), .visualPrev)
    }
}
