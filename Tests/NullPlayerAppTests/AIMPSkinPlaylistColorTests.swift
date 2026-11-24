import XCTest
@testable import NullPlayer

/// How a playlist's flat colours read: `.acs3` writes Delphi colours, `.acs4` on ARGB, where a
/// colour with no alpha is clear (Arc's and W10's lists, over their panes' pictures).
final class AIMPSkinPlaylistColorTests: XCTestCase {
    private func playlist(background: String, delphi: Bool) -> AIMPSkinControl.Playlist {
        let resources = AIMPNode.element("property", ["name": "Resources"], [AIMPNode.property("BackgroundColor", background)])
        return AIMPSkinControl.Playlist(["Resources": resources], resources: [:], delphiColors: delphi)
    }

    func testAFlatZeroIsClearOutsideDelphiSkins() {
        XCTAssertEqual(playlist(background: "0", delphi: false).background, .argb(0), "Arc's list shows its pane")
        XCTAssertEqual(playlist(background: "16777215", delphi: false).background, .argb(0x00FF_FFFF), "W10's clear white")
    }

    func testAFlatZeroIsBlackInDelphiSkins() {
        XCTAssertEqual(playlist(background: "0", delphi: true).background, .argb(0xFF00_0000), "clBlack")
        XCTAssertEqual(playlist(background: "16777215", delphi: true).background, .argb(0xFFFF_FFFF), "clWhite")
    }
}
