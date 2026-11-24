import AppKit

/// `AudioEngine` to `AIMPSkinPlayerSnapshot`, and an AIMP action or provider value back to NullPlayer.
/// Skins name AIMP's own actions (`acPlayerPlay`, `acMainExit`) and data providers (`prvVolume`);
/// each maps to the NullPlayer command that does the same thing. An action NullPlayer has no
/// equivalent for does nothing and is logged once.
///
/// `snapshot` only reads: it runs on the main thread about ten times a second, however often the
/// window asks. What changes between snapshots changes on the engine's events, as the window
/// controller passes them on:
/// - a track's start and finish are counted, and its library details looked up, when the track or
///   the play state changes (`playbackDidChange`);
/// - the playlist rows are rebuilt when the playlist changed (`playlistChanged`, `refreshPlaylist`).
/// Anything that waits on the file system or the library's queue (file sizes, a track's library
/// details) is fetched on a background queue and published back through `onBackgroundUpdate`.
///
/// One per AIMP window controller, released with it: the playlist rows, file sizes,
/// mute and track counts are that skin session's, not the app's.
@MainActor
final class AIMPSkinAudioEngineHost {
    private let engine: AudioEngine
    /// A background fetch finished, or the library's scan or the appearance changed: the host has
    /// more to show.
    private let onBackgroundUpdate: () -> Void
    private var scanObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?

    /// The track playing, nil while stopped, as last seen, and how many tracks have started and
    /// finished since the session began.
    private var lastTrack: PlayedTrack?
    private var tracksStarted = 0
    private var tracksFinished = 0
    /// What only the library knows of the playing track, by its id.
    private var detailsTrack: Track.ID?
    private var details: Details?

    /// The playing track as the library and the file system know it.
    private struct Details {
        var year = 0
        var size: Int64 = 0
        var rating: Int?
        var playCount: Int?
        var lastPlayed: Date?
        var discNumber = 0
        var created: Date?
        var modified: Date?
    }

    /// The playlist's rows, and which build of them they are; `playlistDirty` until rebuilt after a change.
    private var playlistDirty = true
    private var playlistRows = AIMPSkinPlayerSnapshot.Playlist()
    /// The tracks behind `playlistRows`, in order: two tracks whose rows read the same (one file
    /// queued twice) swapping places is a new build, so a row chosen by index is not kept.
    private var playlistIDs: [Track.ID] = []
    private var playlistTextCache: [PlaylistKey: (title: String, seconds: Int)] = [:]
    private var fileSizes: [URL: Int64] = [:]
    /// Files whose size the background queue is reading now.
    private var sizing: Set<URL> = []

    private var mutedVolume: Float?
    /// Where the skin's effect knobs were left.
    private var otherValues: [String: Double] = [:]
    private var unmapped: Set<AIMPAction> = []
    /// AIMP's pitch knob end to end, in cents: an octave each way.
    private static let pitchSpan = 2400.0
    /// NullPlayer's File Info sheet on the window, for the skin playlist's selected row, else the
    /// playing track (`AIMPSkinPlaylistMenuTarget.showFileInfo`).
    var showFileInfo: ((NSWindow?) -> Void)?

    /// The skin's scan lamp follows the library's scan; its Night Mode follows the Mac's appearance
    /// as it changes.
    init(engine: AudioEngine, onBackgroundUpdate: @escaping () -> Void) {
        self.engine = engine
        self.onBackgroundUpdate = onBackgroundUpdate
        scanObserver = NotificationCenter.default.addObserver(forName: MediaLibrary.scanProgressNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // A finished scan may have added the playing track: a lookup that found nothing is
                // tried again, once per scan rather than per frame.
                if !MediaLibrary.shared.isScanning { self?.retryMissingDetails() }
                onBackgroundUpdate()
            }
        }
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onBackgroundUpdate() } }
        }
        // The session begins with whatever is playing: a track already playing has started.
        playbackDidChange()
    }

    /// The session is over: stop following the library's scan and the appearance.
    func stop() {
        scanObserver.map(NotificationCenter.default.removeObserver)
        scanObserver = nil
        appearanceObserver = nil
    }

    /// The player now. Reads only what the engine and this host already hold.
    func snapshot() -> AIMPSkinPlayerSnapshot {
        var player = AIMPSkinPlayerSnapshot()
        player.nightMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch engine.state {
        case .stopped: player.playState = .stopped
        case .playing: player.playState = .playing
        case .paused: player.playState = .paused
        }
        let track = engine.currentTrack
        player.title = track?.title ?? ""
        player.artist = track?.artist ?? ""
        player.album = track?.album ?? ""
        player.bitrate = track?.bitrate ?? 0
        player.sampleRate = track?.sampleRate ?? 0
        player.channels = track?.channels ?? 0
        player.genre = track?.genre ?? ""
        player.fileType = track?.url.pathExtension.uppercased() ?? ""
        if let url = track?.url, url.isFileURL {
            player.fileName = url.deletingPathExtension().lastPathComponent
            player.fileDirectory = url.deletingLastPathComponent().path
        }
        player.year = details?.year ?? 0
        player.fileSize = details?.size ?? 0
        player.rating = details?.rating
        player.playCount = details?.playCount
        player.lastPlayed = details?.lastPlayed
        player.discNumber = details?.discNumber ?? 0
        player.fileCreated = details?.created
        player.fileModified = details?.modified
        // A volume moved anywhere else ends the mute for good: back at 0 later is not still muted.
        if engine.volume != 0 { mutedVolume = nil }
        // Muted, the slider stays at the level the mute keeps, as AIMP's does.
        player.volume = Double(heldMute ?? engine.volume)
        player.balance = (Double(engine.balance) + 1) / 2
        let duration = engine.duration
        // Stopped is at the start in AIMP, whatever the engine last played to (Pioneer's tape
        // counter reads 000).
        let elapsed = engine.state == .stopped ? 0 : engine.currentTime
        player.position = duration.isFinite && duration > 0 ? min(1, max(0, elapsed / duration)) : 0
        player.elapsedSeconds = elapsed.isFinite && elapsed > 0 ? Int(elapsed) : 0
        player.durationSeconds = duration.isFinite && duration > 0 ? Int(duration) : 0
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        player.timeOfDay = (now.hour ?? 0) * 3_600 + (now.minute ?? 0) * 60 + (now.second ?? 0)
        player.shuffle = engine.shuffleEnabled
        player.repeatAll = engine.repeatEnabled
        player.stayOnTop = WindowManager.shared.isAlwaysOnTop
        player.muted = heldMute != nil
        player.eqEnabled = engine.isEQEnabled()
        player.playlistVisible = WindowManager.shared.isPlaylistVisible
        player.libraryVisible = WindowManager.shared.isMediaLibraryVisible
        player.equalizerVisible = WindowManager.shared.isEqualizerVisible
        player.visualizationVisible = WindowManager.shared.isSpectrumVisible
        player.otherValues = otherValues
        player.tracksStarted = tracksStarted
        player.tracksFinished = tracksFinished
        player.eqGains = (0..<engine.eqConfiguration.bandCount).map { Double(engine.getEQBand($0) + 12) / 24 }
        player.preamp = Double(engine.getPreamp() + 12) / 24
        player.speed = Double(engine.playbackSpeed) - 0.5
        player.pitch = min(1, max(0, engine.tuningController.appliedCents / Self.pitchSpan + 0.5))
        player.playlist = playlistRows
        player.playlistIndex = engine.currentIndex
        player.libraryScanning = MediaLibrary.shared.isScanning
        return player
    }

    // MARK: - The engine's events

    /// The track or the play state changed (`updateTrackInfo`, `updatePlaybackState`): a track
    /// starts when playback reaches a new one, and finishes when another replaces it or playback
    /// stops. A new track's library details are looked up.
    func playbackDidChange() {
        let track = engine.currentTrack
        let current = engine.state != .stopped ? track.map(PlayedTrack.init) : nil
        if current != lastTrack {
            if lastTrack != nil { tracksFinished += 1 }
            if current != nil { tracksStarted += 1 }
            lastTrack = current
        }
        guard track?.id != detailsTrack else { return }
        detailsTrack = track?.id
        details = nil
        guard let id = track?.id, let url = track?.url else { return }
        // What only the library knows (year, size, rating, plays), and the file's dates, looked up
        // once per track, off main: the library answers through its own queue, which a scan can hold.
        Self.background.async { [weak self] in
            let found = MediaLibrary.shared.findTrack(byURL: url).map { track -> Details in
                let file = url.isFileURL ? try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) : nil
                return Details(year: track.year ?? 0, size: track.fileSize, rating: track.rating.map { ($0 + 1) / 2 },
                               playCount: track.playCount, lastPlayed: track.lastPlayed, discNumber: track.discNumber ?? 0,
                               created: file?.creationDate, modified: file?.contentModificationDate)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.detailsTrack == id, let found else { return }
                    self.details = found
                    self.onBackgroundUpdate()
                }
            }
        }
    }

    /// A library lookup for the playing track that found nothing is made again (`playbackDidChange`).
    private func retryMissingDetails() {
        guard details == nil, detailsTrack != nil else { return }
        detailsTrack = nil
        playbackDidChange()
    }

    /// What tells one playback from the next: the file, and for a cue sheet's track where it starts
    /// in it, as crossing a cue boundary plays on in the same file.
    private struct PlayedTrack: Equatable {
        let url: URL
        let cueStart: TimeInterval?

        init(_ track: Track) {
            url = track.url
            cueStart = track.cueStartOffset
        }
    }

    /// The level the AIMP mute keeps, while it holds: the engine still at the 0 the mute set. A
    /// volume moved anywhere else (the arrow keys, `MainWindowKeys.stepVolume`) ends it.
    private var heldMute: Float? { engine.volume == 0 ? mutedVolume : nil }

    /// The playlist, a track's tags, or Show Artist / Show Album changed: the rows are rebuilt at
    /// the next `refreshPlaylist`, once for a burst of changes.
    func playlistChanged() { playlistDirty = true }

    /// Rebuilds the rows if the playlist changed since the last time, before a snapshot is taken.
    /// Each track's text is made once per key, so a change costs only the tracks it brings in;
    /// local files' sizes (for the totals) are read on the background queue and fill in after.
    func refreshPlaylist() {
        guard playlistDirty else { return }
        playlistDirty = false
        let fields = PlaylistRowFields.current
        var texts: [PlaylistKey: (title: String, seconds: Int)] = [:]
        var unsized: [URL] = []
        let rows = engine.playlist.map { track -> AIMPSkinPlayerSnapshot.Playlist.Row in
            let key = PlaylistKey(track, fields: fields)
            let text = texts[key] ?? playlistTextCache[key] ?? (fields.text(for: track),
                                                                track.duration.map { $0.isFinite && $0 > 0 ? Int($0) : 0 } ?? 0)
            texts[key] = text
            let bytes = fileSizes[track.url]
            if bytes == nil, track.url.isFileURL { unsized.append(track.url) }
            // Grouped as AIMP groups a playlist by default: by the file's folder; a stream by its album.
            let group = track.url.isFileURL ? track.url.deletingLastPathComponent().lastPathComponent : track.album ?? ""
            return .init(title: text.title, seconds: text.seconds, bytes: bytes ?? 0, group: group,
                         codec: track.url.pathExtension.uppercased(), sampleRate: track.sampleRate ?? 0, bitrate: track.bitrate ?? 0)
        }
        playlistTextCache = texts
        // A rebuild that changes nothing (a track change re-reads every row) is the same playlist.
        let ids = engine.playlist.map(\.id)
        if rows != playlistRows.rows || ids != playlistIDs {
            playlistRows = .init(rows: rows, generation: playlistRows.generation + 1)
            playlistIDs = ids
        }
        guard !unsized.isEmpty else { return }
        let pending = unsized.filter { sizing.insert($0).inserted }
        guard !pending.isEmpty else { return }
        Self.background.async { [weak self] in
            let sizes = pending.map { url in
                (url, ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for (url, size) in sizes {
                        self.fileSizes[url] = size
                        self.sizing.remove(url)
                    }
                    self.playlistDirty = true
                    self.onBackgroundUpdate()
                }
            }
        }
    }

    /// File-system reads and library lookups, in order, off the main thread.
    private static let background = DispatchQueue(label: "com.nullplayer.aimp-host", qos: .utility)

    /// A `PeppyMeterLevelModel` level, 0–100 (dB-linear above its `floor`), as the host's 0–1, which
    /// `pin` scales to AIMP's linear 0–145, where 100 is a meter's 0 dB mark: the level's dBFS
    /// (`PeppyMeterLevels.dbfs`) as an amplitude. RMS at −8 dBFS, a loud master, reads 0 dB; the
    /// spectrum's mean, used before, held most needles in the red. Silence reads 0, not the floor.
    static func meterLevel(_ volume: Double, floor: Double) -> Double {
        guard volume > 0 else { return 0 }
        let amplitude = pow(10, PeppyMeterLevels.dbfs(fromVolume: volume, floor: floor) / 20)
        return min(1, amplitude * 250 / 145)
    }

    private struct PlaylistKey: Hashable {
        var id: Track.ID
        var title: String
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        var video: Bool
        var showArtist: Bool
        var showAlbum: Bool

        init(_ track: Track, fields: PlaylistRowFields) {
            id = track.id
            title = track.title
            artist = track.artist
            album = track.album
            duration = track.duration
            video = track.mediaType == .video
            showArtist = fields.showArtist
            showAlbum = fields.showAlbum
        }
    }

    /// Runs a command; `window` is the skin's, for the window actions. An AIMP action NullPlayer
    /// has no counterpart for is logged once.
    func perform(_ command: AIMPSkinCommand, window: NSWindow?) {
        if AIMPSkinTrace.actions { NSLog("[aimp/action] %@ at %.2f s", command.description, engine.currentTime) }
        switch command {
        case .action(let action): perform(action, window: window)
        case .seek(let seconds): seek(toSeconds: seconds)
        case .removeRow(let index):
            if engine.playlist.indices.contains(index) { engine.removeTrack(at: index) }
        case .playRow(let index):
            if engine.playlist.indices.contains(index) { engine.playTrack(at: index) }
        case .set(let provider, let value): set(provider, to: value)
        }
    }

    /// One of AIMP's named actions.
    private func perform(_ action: AIMPAction, window: NSWindow?) {
        switch action {
        // Play during playback starts the track again, as in AIMP: the decks' counter RESET keys
        // are bound to it while playing (Pioneer CT-F1000, Akai GX-77, Nakamichi BX).
        case .playerPlay: engine.state == .playing ? engine.seek(to: 0) : engine.play()
        case .playerPause: engine.state == .paused ? engine.play() : engine.pause()
        case .playerPlayPause: engine.state == .playing ? engine.pause() : engine.play()
        case .playerStop: engine.stop()
        case .playerPrevTrack: engine.previous()
        case .playerNextTrack: engine.next()
        case .playerShuffle, .playerShuffleMode: engine.shuffleEnabled.toggle()
        case .playerRepeat, .playerRepeatPlaylist, .playerRepeatTrack: engine.repeatEnabled.toggle()
        case .playerOpenFiles, .playlistAddFiles, .playerOpen: MenuActions.shared.openFile()
        case .playlistAddFolder: MenuActions.shared.openFolder()
        case .playlistAddURL: _ = PlaylistMenuBuilder.promptAddURL()
        case .mainExit: NSApp.terminate(nil)
        case .mainAbout: (NSApp.delegate as? AppDelegate)?.showAbout()
        // As NullPlayer's own minimize: a borderless window takes no `miniaturize` until it is
        // made miniaturizable, which this does, the skin's other windows going with it.
        case .mainMinimize: WindowManager.shared.miniaturizeAllManagedWindows()
        case .mainStayOnTop: WindowManager.shared.isAlwaysOnTop.toggle()
        case .equalizerSwitch: engine.setEQEnabled(!engine.isEQEnabled())
        case .mainOpenFiles: MenuActions.shared.openFile()
        case .mainDSPManager, .mainDSPManagerEQ: WindowManager.shared.toggleEqualizer()
        case .playerSeekForward, .playerSeekBackward:
            seek(toSeconds: engine.currentTime + (action == .playerSeekForward ? 5 : -5))
        case .playlistShow, .mainShowPlaylist: WindowManager.shared.togglePlaylist()
        case .mainShowMusicLibrary, .musicLibraryShow: WindowManager.shared.toggleMediaLibrary()
        case .equalizerShow, .mainShowEqualizer: WindowManager.shared.toggleEqualizer()
        case .visualizationShow: WindowManager.shared.toggleSpectrum()
        case .playableFileShowFileInfoAtCursor, .playlistFocusedItemShowQTE, .playableFileShowQTE:
            showFileInfo?(window)
        // The playing file: its tags (when the library has it), its folder, it or its tags copied.
        // Not in the library, the File Info sheet of the track playing when asked, not of whatever
        // is selected or playing once the lookup answers.
        case .sendToTagEditor, .utilsTagEditor:
            guard let playing = engine.currentTrack else { break }
            let url = playing.url
            Self.background.async { [weak window] in
                let track = MediaLibrary.shared.findTrack(byURL: url)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let track { return EditTagsPanel(track: track).show() }
                        guard let window else { return }
                        PlaylistMenuBuilder.fileInfoAlert(for: playing).beginSheetModal(for: window)
                    }
                }
            }
        case .playlistOpenFolderWithSelectedFile:
            if let url = engine.currentTrack?.url, url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .playableFileCopyInfoToClipboard:
            if let track = engine.currentTrack {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.displayTitle, forType: .string)
            }
        case .playableFileCopyFileToClipboard:
            if let url = engine.currentTrack?.url, url.isFileURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
        // A twentieth of the range a press (TEAC CD-RW890's VOLUME − and +).
        case .playerVolumeUp, .playerVolumeDown:
            let step: Float = action == .playerVolumeUp ? 0.05 : -0.05
            engine.volume = min(1, max(0, engine.volume + step))
            mutedVolume = nil
        case .musicLibraryAddFiles: Self.addFilesOrFoldersToLibrary()
        // NullPlayer has no mute: the volume goes to 0 and comes back. Not WMP's toggle
        // (`WMPAudioEngineHost`), which reads any volume of 0 as muted: AIMP's `acPlayerVolumeMute`
        // is on only while this mute holds, and moving the volume ends it (Denon Classic Style's
        // speakers script reads it before muting).
        case .playerVolumeMute:
            if let restore = heldMute {
                engine.volume = restore
                mutedVolume = nil
            } else {
                mutedVolume = engine.volume
                engine.volume = 0
            }
        default:
            if unmapped.insert(action).inserted { NSLog("AIMPSkin: no NullPlayer action for '%@'", action.name) }
        }
    }

    /// Asks for files or folders and adds them to the library (folders scanned), as AIMP's
    /// `acMusicLibraryAddFiles` does with one panel. Not the library browser's `addFiles` and
    /// `addWatchFolder`: those take one kind each, and act on the browser's own model.
    static func addFilesOrFoldersToLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Add files or folders to the music library"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let files = urls.filter { !folders.contains($0) }
        if !files.isEmpty { MediaLibrary.shared.addTracks(urls: files) }
        for folder in folders { MediaLibrary.shared.scanFolder(folder) }
    }

    /// One of the player's values set to `value`, 0–1, turned into the engine's units.
    private func set(_ provider: AIMPSkinProvider, to value: Double) {
        let value = min(1, max(0, value))
        switch provider {
        case .volume:
            engine.volume = Float(value)
            mutedVolume = nil
        case .balance: engine.balance = Float(value * 2 - 1)
        // AIMP's speed and tempo are NullPlayer's (tempo-preserving) speed, held at 1× near the middle
        // so it can be found again.
        case .speed:
            let speed = value + 0.5
            engine.setPlaybackSpeed(abs(speed - 1) < 0.03 ? 1 : Float(speed))
        // AIMP's pitch is NullPlayer's pitch shift, the Reference Tuning offset, ±1,200 cents; off
        // near the middle, so it can be found again. It replaces a Reference Tuning chosen elsewhere.
        case .pitch:
            let cents = (value - 0.5) * Self.pitchSpan
            if abs(cents) < 15 { engine.setTuningPreset(.off) } else { engine.setTuningOffsetCents(cents) }
        case .preamp: engine.setPreamp(Float(value * 24 - 12))
        case .equalizerBand(let band): engine.setEQBand(band, gain: Float(value * 24 - 12))
        case .named(let name): otherValues[name] = value
        case .position: seek(to: value)
        }
    }

    /// A seek bar dragged to `fraction` of the track: its whole length, the end included.
    private func seek(to fraction: Double) {
        let duration = engine.duration
        guard duration.isFinite, duration > 0 else { return }
        engine.seek(to: min(1, max(0, fraction)) * duration)
    }

    /// A script's seek or a REW/FF step to `seconds`, held a second short of the end: a seek past it
    /// left the engine parked at the last frame with the REW/FF timers still winding. The track plays
    /// out from there and the next one starts.
    private func seek(toSeconds seconds: Double) {
        let duration = engine.duration
        let end = duration.isFinite && duration > 0 ? duration - 1 : .infinity
        engine.seek(to: max(0, min(end, seconds)))
    }
}
