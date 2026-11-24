import AppKit

/// The queue commands the skin's own playlist answers: NullPlayer's playlist menu
/// (`PlaylistMenuBuilder`) on a right-click over its rows and behind its `pmPlaylistMain` / `pmMisc`
/// keys, and the Remove and Misc section menus behind `pmDelete` and `pmSorting`, as `.wal`'s
/// `WinampModernPlaylistMenuTarget` answers its `PE_*` buttons. The selection is the skin's
/// (`AIMPSkinState.Lists.playlistSelection`); File Info is NullPlayer's sheet (`fileInfoAlert`).
///
/// One per window controller; `runtime` is the skin running now and `window` the one the last menu
/// opened over, which a sheet attaches to.
@MainActor
final class AIMPSkinPlaylistMenuTarget: NSObject, PlaylistMenuTarget {
    weak var runtime: AIMPSkinRuntime?
    weak var window: NSWindow?

    private var engine: AudioEngine { WindowManager.shared.audioEngine }

    /// The selected rows still in the playlist.
    var selection: Set<Int> {
        let rows = engine.playlist.indices
        return (runtime?.state.lists.playlistSelection ?? []).filter(rows.contains)
    }

    private func select(_ rows: Set<Int>, anchor: Int?) {
        guard let runtime else { return }
        runtime.state.lists.playlistSelection = rows
        runtime.state.lists.playlistAnchor = anchor
    }

    /// The track File Info is about: the one selected row, else the playing track.
    var fileInfoTrack: Track? {
        let selection = selection
        if selection.count == 1, let row = selection.first { return engine.playlist[row] }
        return engine.currentTrack
    }

    /// NullPlayer's playlist menu over the skin's playlist; `clickedRow` outside the selection is
    /// selected first.
    func menu(clickedRow: Int?) -> NSMenu {
        PlaylistMenuBuilder.menu(target: self, clickedRow: clickedRow,
                                 state: .init(selectedRows: selection, hasTracks: !engine.playlist.isEmpty),
                                 autoenablesItems: false)
    }

    func selectForMenu(_ row: Int) { select([row], anchor: row) }

    func playSelected(_ sender: Any?) {
        guard let row = selection.min() else { return }
        engine.playTrack(at: row)
    }

    // MARK: Removing

    func removeSelected(_ sender: Any?) {
        PlaylistMenuBuilder.removeTracks(at: selection)
        select([], anchor: nil)
    }

    func cropSelection(_ sender: Any?) {
        let keep = selection
        guard !keep.isEmpty else { return }
        PlaylistMenuBuilder.cropPlaylist(to: keep)
        select([], anchor: nil)
    }

    func removeAll(_ sender: Any?) {
        engine.clearPlaylist()
        select([], anchor: nil)
    }

    func removeDeadFiles(_ sender: Any?) {
        PlaylistMenuBuilder.removeDeadFiles()
        select([], anchor: nil)
    }

    // MARK: Selecting

    func selectAll(_ sender: Any?) { select(Set(engine.playlist.indices), anchor: engine.playlist.isEmpty ? nil : 0) }
    func selectNone(_ sender: Any?) { select([], anchor: nil) }
    func invertSelection(_ sender: Any?) {
        select(Set(engine.playlist.indices).subtracting(selection), anchor: nil)
    }

    // MARK: Sorting

    func sortByTitle(_ sender: Any?) { engine.sortPlaylist(by: .title) }
    func sortByArtist(_ sender: Any?) { engine.sortPlaylist(by: .artist) }
    func sortByAlbum(_ sender: Any?) { engine.sortPlaylist(by: .album) }
    func sortByFilename(_ sender: Any?) { engine.sortPlaylist(by: .filename) }
    func sortByPath(_ sender: Any?) { engine.sortPlaylist(by: .path) }
    func reverse(_ sender: Any?) { engine.reversePlaylist() }
    func randomize(_ sender: Any?) { engine.shufflePlaylist() }

    // MARK: File Info

    /// NullPlayer's File Info sheet on the skin's window, for the selected row, else the playing
    /// track: the menu's item and AIMP's `acPlayableFileShowFileInfoAtCursor` alike.
    func showFileInfo(_ sender: Any?) {
        guard let window, let track = fileInfoTrack else { return }
        PlaylistMenuBuilder.fileInfoAlert(for: track).beginSheetModal(for: window)
    }
}
