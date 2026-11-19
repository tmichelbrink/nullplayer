import XCTest
@testable import NullPlayer

final class PlaylistDropTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PlaylistDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testOnlyPlayableDropsAreAccepted() throws {
        let text = folder.appendingPathComponent("notes.txt")
        try Data().write(to: text)
        XCTAssertFalse(PlaylistDrop.accepts([text]))
        XCTAssertTrue(PlaylistDrop.accepts([folder.appendingPathComponent("album.cue")]))
        XCTAssertTrue(PlaylistDrop.accepts([folder.appendingPathComponent("song.mp3")]))
    }

    /// A cue sheet and the audio beside it, dropped together, add the album once; a plain audio file
    /// is one track; anything else is left to the folder search.
    func testACueSheetAndItsAudioNameTheAlbumOnce() throws {
        let audio = folder.appendingPathComponent("album.flac")
        try Data().write(to: audio)
        let cue = folder.appendingPathComponent("album.cue")
        try """
        FILE "album.flac" WAVE
        TRACK 01 AUDIO
            TITLE "One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Two"
            INDEX 01 01:00:00
        """.write(to: cue, atomically: true, encoding: .utf8)
        let single = folder.appendingPathComponent("single.mp3")
        try Data().write(to: single)

        let tracks = PlaylistDrop.namedTracks([cue, audio, single, folder.appendingPathComponent("notes.txt")])
        XCTAssertEqual(tracks.map(\.title), ["One", "Two", "single"])
    }

    func testCueSheetsAloneAreDeliveredAtOnceAndOnlyWithTracks() {
        let cue = folder.appendingPathComponent("album.cue")
        var delivered: [[Track]] = []
        PlaylistDrop.gather([cue], named: []) { delivered.append($0) }
        XCTAssertTrue(delivered.isEmpty)
        PlaylistDrop.gather([cue], named: [Track(url: folder.appendingPathComponent("a.mp3"))]) { delivered.append($0) }
        XCTAssertEqual(delivered.map(\.count), [1])
    }

    /// A named file and a folder holding it and one more: delivered once, on the main thread, the
    /// named track first and the folder's other track after it, the named one not added twice.
    /// The folder is given by its real path, as a Finder drop's are: the search reports what it
    /// finds under the real path (`/private/var/...`, not the temporary folder's `/var/...`).
    /// `resolvingSymlinksInPath()` drops `/private` again, so `realpath` it is.
    func testAMixedDropDeliversTheNamedTrackFirstAndOnce() throws {
        let real = try XCTUnwrap(realpath(self.folder.path, nil))
        defer { free(real) }
        let folder = URL(fileURLWithPath: String(cString: real), isDirectory: true)
        let named = folder.appendingPathComponent("b.mp3")
        let other = folder.appendingPathComponent("a.mp3")
        try Data([0]).write(to: named)
        try Data([0]).write(to: other)
        let urls = [named, folder]
        let delivered = expectation(description: "delivered")
        var calls: [[URL]] = []
        PlaylistDrop.gather(urls, named: PlaylistDrop.namedTracks(urls)) { tracks in
            XCTAssertTrue(Thread.isMainThread)
            calls.append(tracks.map(\.url))
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(calls, [[named, other]])
    }
}
