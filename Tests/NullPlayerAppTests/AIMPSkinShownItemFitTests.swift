import XCTest
@testable import NullPlayer

/// A fixed window grows to hold an item that starts hidden once it is shown (Cassette-3D's VU meter
/// panel over its bottom-docked cassette), as AIMP fits such a window to what it holds.
final class AIMPSkinShownItemFitTests: XCTestCase {
    func testCassette3DGrowsForItsVUMeters() throws {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NullPlayer/AIMPSkins/Cassette-3D.acs4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "Cassette-3D is not installed")
        let skin = try AIMPSkinLoader.load(contentsOf: file)
        let natural = try XCTUnwrap(skin.naturalSize(form: nil))
        XCTAssertEqual(AIMPSkinRenderer.fittedSize(skin, natural: natural, state: AIMPSkinState()), natural,
                       "hidden meters take no room")

        var state = AIMPSkinState()
        state.script["VU_Container"].visible = true
        let fitted = AIMPSkinRenderer.fittedSize(skin, natural: natural, state: state)
        XCTAssertEqual(fitted.width, natural.width)
        XCTAssertEqual(fitted.height, 610, "206-px meters less their 36-px overlap over the 440-px cassette")

        // Laid out at the fitted size, the cassette keeps its whole 440 px below the meters' slot.
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: state)
        let tree = try XCTUnwrap(AIMPSkinLayout(flow: flow).tree(size: fitted))
        let cassette = try XCTUnwrap(tree.offers.namedRects["Cassette_Container"])
        let meters = try XCTUnwrap(tree.offers.namedRects["VU_Container"])
        XCTAssertEqual(cassette.height, 440)
        XCTAssertEqual(cassette.maxY, fitted.height)
        XCTAssertEqual(meters.minY, 0)
        XCTAssertEqual(meters.maxY - 36, cassette.minY, "the meters overlap the cassette by their -36 margin")
    }
}
