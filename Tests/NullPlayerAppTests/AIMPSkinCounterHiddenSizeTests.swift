import XCTest
@testable import NullPlayer

/// A main form's items the skin's own state hides at its start take no room (AIMP 5.40's opening sizes).
final class AIMPSkinCounterHiddenSizeTests: XCTestCase {
    /// Lux & Nox's player sits under its welcome screen, shown at another position of the same counter.
    func testLuxNoxOpensAtItsWelcomeScreenAlone() throws {
        let skin = try AIMPCorpusSkin.load("1199-Lux_Nox_v1.11.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 870, height: 550),
                       "AIMP 5.40 opens the 870x550 welcome screen, not it stacked over the hidden player")
    }

    /// Messa's dock area shows only while its playlist site does (a commutator over the site).
    func testMessaOpensWithoutItsHiddenDockArea() throws {
        let skin = try AIMPCorpusSkin.load("1205-Messa_v2.4.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 562, height: 247),
                       "AIMP 5.40 opens the 562x247 player alone")
    }

    /// Euphoria Lux's playlist window docks in a 216-px site: the site's minimum, not room for more rows.
    func testEuphoriaLuxOpensAtItsPlaylistSiteMinimum() throws {
        let skin = try AIMPCorpusSkin.load("917-Euphoria_Lux_v2.3.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 380, height: 406),
                       "AIMP 5.40 opens the main form with its docked playlist at the site's minimum")
    }

    /// Arctur's top bar says `AllowResizeByHeight` False: its 61-px picture stacks over the playlist site.
    func testArcturKeepsItsTopBarOverItsPlaylistSite() throws {
        let skin = try AIMPCorpusSkin.load("829-Arctur_v5.acs4")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 874, height: 281),
                       "AIMP 5.40 opens the 61-px bar over the 220-px site")
    }
}
