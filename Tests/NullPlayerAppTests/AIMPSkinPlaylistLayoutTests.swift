import XCTest
@testable import NullPlayer

/// The playlist as AIMP lays it out: a header over each group, each track on two lines with its
/// format and size under the title (eX-Black's, AIMP 5.40's sample playlist).
final class AIMPSkinPlaylistLayoutTests: XCTestCase {
    /// Rows of their own heights, a header band above the first of each group; a click over a header
    /// picks no track.
    func testRowsCarryTheirGroupsHeaders() {
        let groups = ["a", "a", "b", "b", "b"]
        let rows = AIMPSkinLayout.Rows(top: 0, count: groups.count, room: 100) { row in
            (row == 0 || groups[row] != groups[row - 1] ? 20 : 0, 30)
        }
        XCTAssertEqual(rows.slots.map(\.top), [0, 50, 80])
        XCTAssertEqual(rows.slots.map(\.header), [20, 0, 20])
        XCTAssertEqual(rows.visible, 2, "the third row, 80-130, runs past the 100-px list")
        XCTAssertNil(rows.row(at: 10), "the first group's header")
        XCTAssertEqual(rows.row(at: 25), 0)
        XCTAssertEqual(rows.row(at: 60), 1)
        XCTAssertNil(rows.row(at: 90), "the second group's header")
    }

    /// Scrolled past the end, the list stops where its last row shows at the bottom.
    func testRowsStopAtTheLastRow() {
        let rows = AIMPSkinLayout.Rows(top: 10, count: 5, room: 70) { _ in (0, 30) }
        XCTAssertEqual(rows.first, 3)
        XCTAssertEqual(rows.slots.map(\.row), [3, 4])
    }

    /// AIMP's second line: `MP3 :: 22 kHz, 32 kbps, 614.13 KB`.
    func testATracksDetailsReadAsAIMPs() {
        let row = AIMPSkinPlayerSnapshot.Playlist.Row(title: "Sample Artist - Sample Track 1", seconds: 158, bytes: 628_869,
                                                      group: "sample", codec: "MP3", sampleRate: 22050, bitrate: 32)
        XCTAssertEqual(row.details, "MP3 :: 22 kHz, 32 kbps, 614.13 KB")
        XCTAssertEqual(AIMPSkinPlayerSnapshot.Playlist.Row(title: "Stream", seconds: 0).details, "")
    }

    /// The header's and second line's fonts, and the marks and switches by their earlier names too.
    @MainActor func testAPlaylistReadsItsHeaderSecondLineAndMarks() throws {
        let resources = try AIMPSkinScriptTests.node("""
        <property name="Resources">
          <property name="HeaderFont" value="Segoe UI,5460819,13,0"/>
          <property name="ItemLine1Font" value="Segoe UI,4802889,15,0"/>
          <property name="ItemLine2Font" value="Tahoma,6710886,11,0"/>
          <property name="HeaderExpandButtons" value="Playlist.Resources.HeaderExpandButtons"/>
          <property name="SkinMarks" value="Playlist.Resources.SkinMarks"/>
          <property name="SkinSwitches" value="Playlist.Resources.SkinSwitches"/>
        </property>
        """)
        let style = AIMPSkinControl.Playlist(["Resources": resources], resources: [:], delphiColors: true)
        XCTAssertEqual(style.headerFont.height, 13)
        XCTAssertEqual(style.fonts[.normal]?.height, 15)
        XCTAssertEqual(style.detailFonts[.normal]?.height, 11)
        XCTAssertEqual(style.expandButtons, "Playlist.Resources.HeaderExpandButtons")
        XCTAssertEqual(style.marks, "Playlist.Resources.SkinMarks")
        XCTAssertEqual(style.switches, "Playlist.Resources.SkinSwitches")
        XCTAssertFalse(style.classic)
    }
}
