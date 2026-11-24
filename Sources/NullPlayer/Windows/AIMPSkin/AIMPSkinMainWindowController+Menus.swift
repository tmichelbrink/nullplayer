import AppKit

/// The menus a skin's keys pop up that NullPlayer has its own of.
extension AIMPSkinMainWindowController {
    /// NullPlayer's menu like one a skin pops up (`AIMPSkinPopup`): the EQ presets; the playlist's,
    /// through `PlaylistMenuBuilder` over the skin playlist's selection (`playlist`): the whole menu, its
    /// Remove and Misc sections, adding files; and the library window's own (adding to the library,
    /// rescanning it). `clickedRow` is the playlist row a right-click was over.
    @MainActor static func popupMenu(_ popup: AIMPSkinPopup, playlist: AIMPSkinPlaylistMenuTarget, clickedRow: Int?) -> NSMenu {
        let engine = WindowManager.shared.audioEngine
        let menu = NSMenu()
        // Items honour their own enabled state.
        menu.autoenablesItems = false
        switch popup {
        case .library:
            menu.addItem(ClosureMenuItem(title: "Add Files or Folders to Library…") { AIMPSkinAudioEngineHost.addFilesOrFoldersToLibrary() })
            menu.addItem(ClosureMenuItem(title: "Rescan Library") { MediaLibrary.shared.rescanWatchFolders() })
        case .playlist:
            return playlist.menu(clickedRow: clickedRow)
        case .remove:
            return PlaylistMenuBuilder.removeMenu(target: playlist, hasSelection: !playlist.selection.isEmpty)
        case .sort:
            return PlaylistMenuBuilder.miscMenu(target: playlist, selectedRows: playlist.selection,
                                                canShowFileInfo: playlist.fileInfoTrack != nil)
        case .add:
            menu.addItem(ClosureMenuItem(title: "Add URL…") { _ = PlaylistMenuBuilder.promptAddURL() })
            menu.addItem(ClosureMenuItem(title: "Add Directory…") { PlaylistMenuBuilder.promptAddDirectory {} })
            menu.addItem(ClosureMenuItem(title: "Add Files…") { _ = PlaylistMenuBuilder.promptAddFiles() })
        // The view builds a skin's own menus (`AIMPSkinMainView.menu`); an unavailable one opens nothing.
        case .custom, .unavailable: break
        case .managePlaylist:
            menu.addItem(ClosureMenuItem(title: "Load Playlist…") { _ = PlaylistMenuBuilder.promptLoadPlaylist() })
            menu.addItem(ClosureMenuItem(title: "Save Playlist…") { PlaylistMenuBuilder.promptSaveQueue() })
        case .equalizer:
            let toggle = ClosureMenuItem(title: "Equalizer On") { engine.setEQEnabled(!engine.isEQEnabled()) }
            toggle.state = engine.isEQEnabled() ? .on : .off
            menu.addItem(toggle)
            menu.addItem(.separator())
            for preset in EQPreset.allPresets {
                menu.addItem(ClosureMenuItem(title: preset.name) {
                    preset.apply(to: engine)
                    if !engine.isEQEnabled() { engine.setEQEnabled(true) }
                })
            }
        }
        return menu
    }
}
