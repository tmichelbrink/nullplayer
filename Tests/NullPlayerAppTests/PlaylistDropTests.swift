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
}
