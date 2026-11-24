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

/// A main form's items the skin's own state hides at its start take no room (AIMP 5.40's opening sizes).
final class AIMPSkinCounterHiddenSizeTests: XCTestCase {
    private func corpusSkin(_ name: String) throws -> AIMPSkin {
        let dirs: [String?] = [ProcessInfo.processInfo.environment["AIMP_TEST_SKINS"],
                               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NullPlayer/AIMPSkins").path]
        guard let file = dirs.compactMap({ $0 }).map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("\(name) is not installed") }
        return try AIMPSkinLoader.load(contentsOf: file)
    }

    /// Lux & Nox's player sits under its welcome screen, shown at another position of the same counter.
    func testLuxNoxOpensAtItsWelcomeScreenAlone() throws {
        let skin = try corpusSkin("1199-Lux_Nox_v1.11.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 870, height: 550),
                       "AIMP 5.40 opens the 870x550 welcome screen, not it stacked over the hidden player")
    }

    /// Messa's dock area shows only while its playlist site does (a commutator over the site).
    func testMessaOpensWithoutItsHiddenDockArea() throws {
        let skin = try corpusSkin("1205-Messa_v2.4.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 562, height: 247),
                       "AIMP 5.40 opens the 562x247 player alone")
    }

    /// Euphoria Lux's playlist window docks in a 216-px site: the site's minimum, not room for more rows.
    func testEuphoriaLuxOpensAtItsPlaylistSiteMinimum() throws {
        let skin = try corpusSkin("917-Euphoria_Lux_v2.3.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 380, height: 406),
                       "AIMP 5.40 opens the main form with its docked playlist at the site's minimum")
    }

    /// Arctur's top bar says `AllowResizeByHeight` False: its 61-px picture stacks over the playlist site.
    func testArcturKeepsItsTopBarOverItsPlaylistSite() throws {
        let skin = try corpusSkin("829-Arctur_v5.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 874, height: 281),
                       "AIMP 5.40 opens the 61-px bar over the 220-px site")
    }
}
