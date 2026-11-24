import XCTest
@testable import NullPlayer

/// The skin's own playlist selects as NullPlayer's playlists do (click, Shift, Command) and opens
/// NullPlayer's playlist menu over that selection (`AIMPSkinPlaylistMenuTarget`). Tracks are
/// placeholders that never play; the queue is emptied again after each test.
@MainActor
final class AIMPSkinPlaylistMenuTests: XCTestCase {
    private var engine: AudioEngine { WindowManager.shared.audioEngine }

    override func tearDown() async throws {
        engine.clearPlaylist()
    }

    func testAClickSelectsShiftExtendsAndCommandToggles() {
        var lists = AIMPSkinState.Lists()
        lists.select(2)
        XCTAssertEqual(lists.playlistSelection, [2])
        lists.select(5, extending: true)
        XCTAssertEqual(lists.playlistSelection, [2, 3, 4, 5], "from the anchor")
        lists.select(0, extending: true)
        XCTAssertEqual(lists.playlistSelection, [0, 1, 2], "the anchor stays")
        lists.select(7, toggling: true)
        XCTAssertEqual(lists.playlistSelection, [0, 1, 2, 7])
        lists.select(1, toggling: true)
        XCTAssertEqual(lists.playlistSelection, [0, 2, 7])
        lists.select(nil)
        XCTAssertEqual(lists.playlistSelection, [])
        XCTAssertNil(lists.playlistAnchor)
        lists.select(3)
        lists.setSearch(.playlist, "x")
        XCTAssertEqual(lists.playlistSelection, [], "a search clears the selection")
    }

    func testTheMenuActsOnTheSelectionAndARightClickedRowJoinsIt() throws {
        let (target, runtime) = try make(tracks: 4)
        runtime.state.lists.playlistSelection = [1, 2]

        var menu = target.menu(clickedRow: 2)
        XCTAssertEqual(runtime.state.lists.playlistSelection, [1, 2], "a row inside the selection keeps it")
        XCTAssertFalse(try XCTUnwrap(menu.item(withTitle: "File Info...")).isEnabled, "File Info is for one row")

        menu = target.menu(clickedRow: 3)
        XCTAssertEqual(runtime.state.lists.playlistSelection, [3], "a row outside it is selected first")
        XCTAssertTrue(try XCTUnwrap(menu.item(withTitle: "File Info...")).isEnabled)
        XCTAssertEqual(target.fileInfoTrack?.title, "Track 3")

        runtime.state.lists.playlistSelection = [0, 2]
        target.removeSelected(nil)
        XCTAssertEqual(engine.playlist.map(\.title), ["Track 1", "Track 3"])
        XCTAssertEqual(runtime.state.lists.playlistSelection, [])

        runtime.state.lists.playlistSelection = [1]
        target.cropSelection(nil)
        XCTAssertEqual(engine.playlist.map(\.title), ["Track 3"])
    }

    /// With a quick search, Select All and Invert Selection reach only the rows it shows, so Remove
    /// Selected cannot take a hidden track: here the search shows none of them.
    func testSelectionCommandsStayInsideTheQuickSearch() throws {
        let (target, runtime) = try make(tracks: 4)
        runtime.state.lists.playlistSearch = "no such track"
        target.selectAll(nil)
        XCTAssertEqual(runtime.state.lists.playlistSelection, [])
        target.invertSelection(nil)
        XCTAssertEqual(runtime.state.lists.playlistSelection, [], "the hidden tracks stay out")
        runtime.state.lists.playlistSelection = [0, 1]
        target.removeSelected(nil)
        XCTAssertEqual(engine.playlist.count, 4, "a hidden selected track is not removed")
    }

    func testTheSectionMenusComeFromTheBuilder() throws {
        let (target, runtime) = try make(tracks: 2)
        runtime.state.lists.playlistSelection = []
        let remove = AIMPSkinMainWindowController.popupMenu(.remove, playlist: target, clickedRow: nil)
        XCTAssertEqual(remove.items.map(\.title), ["Remove Selected", "Crop Selection", "Remove All", "Remove Dead Files"])
        XCTAssertFalse(remove.items[0].isEnabled, "nothing selected")
        let misc = AIMPSkinMainWindowController.popupMenu(.sort, playlist: target, clickedRow: nil)
        XCTAssertNotNil(misc.item(withTitle: "Sort")?.submenu)
        XCTAssertTrue(try XCTUnwrap(misc.item(withTitle: "File Info...")).target === target)
    }

    // MARK: - Helpers

    private func make(tracks: Int) throws -> (AIMPSkinPlaylistMenuTarget, AIMPSkinRuntime) {
        engine.clearPlaylist()
        engine.appendTracks((0..<tracks).map { index in
            Track(url: URL(fileURLWithPath: "/nonexistent/aimp-menu-\(index).mp3"), title: "Track \(index)")
        })
        let runtime = AIMPSkinRuntime(skin: try AIMPSkinLoader.load(data: AIMPSkinSurfaceRoutingTests.skinWithOwnPlaylist()), player: .probe)
        let target = AIMPSkinPlaylistMenuTarget()
        target.runtime = runtime
        return (target, runtime)
    }
}
