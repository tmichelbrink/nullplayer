import XCTest
@testable import NullPlayer

/// The skin's own playlist follows the playing track by the rule every family's playlist uses
/// (`PlayingRowPlacement`): the least scroll that shows it, or under shuffle the row centred.
@MainActor
final class AIMPSkinPlaylistFollowTests: XCTestCase {
    private func runtime(playing index: Int, shuffle: Bool = false) throws -> (AIMPSkinRuntime, AIMPSkinPlayerSnapshot) {
        var player = AIMPSkinPlayerSnapshot.probe
        player.playlist = .init(rows: (1...40).map { .init(title: "Track \($0)", seconds: 120) })
        player.playlistIndex = index
        player.shuffle = shuffle
        return (AIMPSkinRuntime(skin: try AIMPSkinScriptTests.skin(scripts: [:]), player: player), player)
    }

    /// Before a frame says how many rows show, the follow waits; the first frame scrolls to the
    /// playing row (a skin just loaded follows it too).
    func testFollowWaitsForTheFirstFrame() throws {
        let (runtime, _) = try runtime(playing: 25)
        XCTAssertEqual(runtime.state.lists.playlistTop, 0)
        runtime.notePlaylistRows(10)
        XCTAssertEqual(runtime.state.lists.playlistTop, 16, "the least scroll: the playing row at the foot")
    }

    /// Without shuffle a row already in view leaves the scroll alone; one below scrolls just far
    /// enough to show it.
    func testEdgePlacementWithoutShuffle() throws {
        var (runtime, player) = try runtime(playing: 0)
        runtime.notePlaylistRows(10)
        XCTAssertEqual(runtime.state.lists.playlistTop, 0)
        player.playlistIndex = 6
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 0, "row 6 is in view")
        player.playlistIndex = 12
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 3, "row 12 at the foot of ten rows")
    }

    /// Under shuffle the playing row is centred, in view or not, and clamped at the ends.
    func testCentredUnderShuffle() throws {
        var (runtime, player) = try runtime(playing: 0, shuffle: true)
        runtime.notePlaylistRows(10)
        XCTAssertEqual(runtime.state.lists.playlistTop, 0, "clamped at the top")
        player.playlistIndex = 20
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 15)
        player.playlistIndex = 18
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 13, "centred again though already in view")
        player.playlistIndex = 39
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 30, "clamped at the bottom")
    }

    /// A scroll the user made stays until the track changes.
    func testUserScrollStaysUntilTheTrackChanges() throws {
        var (runtime, player) = try runtime(playing: 2)
        runtime.notePlaylistRows(10)
        runtime.state.lists.playlistTop = 20
        player.volume = 0.3
        runtime.update(player: player)
        XCTAssertEqual(runtime.state.lists.playlistTop, 20)
        runtime.notePlaylistRows(12)
        XCTAssertEqual(runtime.state.lists.playlistTop, 20, "a resize does not pull it back")
    }
}
