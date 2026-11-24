import AppKit
import NullPlayerCore
import UniformTypeIdentifiers

/// The AIMP-mode main window: one borderless window showing the selected skin's main form. Loads
/// the `.acs5`/`.acs4`/`.acs3`/`.acs` off the main thread and shows it through `AIMPSkinMainView`; with none
/// selected, or one that fails to load, the view's app-authored panel stands in. The window's size is
/// the form's natural size times the UI scale; a reload or a restored frame keeps its top-left corner.
final class AIMPSkinMainWindowController: NSWindowController, NSWindowDelegate, SkinFileMainWindow, SkinSurfaceRouter, SkinOwnedWindowsProviding {
    static let placeholderSize = AIMPSkinMainView.unskinnedSize

    private let importer: AIMPSkinImporter
    private let skinView = AIMPSkinMainView()
    /// The skin's other windows (speakers, amplifier, equalizer, its own playlist and library).
    private let forms: AIMPSkinFormWindowMaterializer
    /// NullPlayer's library browser over the skin's library lists, one per skin.
    let libraryHost = AIMPSkinLibraryHost(fallbackStyle: unskinnedSurfaceStyle)
    /// The skin playlist's menus and File Info, over its selection.
    let playlistMenu = AIMPSkinPlaylistMenuTarget()
    private var coverArt: CGImage?
    private var artworkTrackID: Track.ID?
    private var artworkTask: Task<Void, Never>?
    /// The playing track's waveform in columns, for the skin's waveform seek bars, and its loading.
    private var waveform: [UInt16] = []
    private var waveformTask: Task<Void, Never>?
    let skinLoad = SkinLoadTask()
    /// The skin's level meters: each channel's RMS with VU ballistics, from the stereo tap.
    private let levelModel = PeppyMeterLevelModel(consumerId: "aimpSkinLevels")
    /// The player as this skin session sees it; a file size, the library's scan or a track's
    /// details fetched off the main thread refresh the skin.
    private lazy var engineHost: AIMPSkinAudioEngineHost = {
        let host = AIMPSkinAudioEngineHost(engine: WindowManager.shared.audioEngine) { [weak self] in
            self?.refreshHostState()
        }
        host.showFileInfo = { [weak self] window in
            guard let self else { return }
            self.playlistMenu.window = window
            self.playlistMenu.showFileInfo(nil)
        }
        return host
    }()
    /// The skin file on screen, nil while the unskinned panel stands in.
    private(set) var loadedSkinURL: URL?
    /// The loaded skin, running; every window showing one of its forms draws from it.
    private var runtime: AIMPSkinRuntime?
    /// Set once the first skin (or the unskinned panel) is up; until then the playlist and library
    /// opens a launch restores wait in `opensAwaitingSkin`.
    private var skinPresented = false
    private var opensAwaitingSkin: [() -> Void] = []
    private var playlistRefreshPending = false
    /// NullPlayer's own windows (EQ, a skin without its own playlist or library) wear AIMP's dark
    /// grey with its orange accent beside every skin, never another family's chrome: an AIMP skin
    /// authors no palette for windows it does not draw. `SkinnedSurfaceStyle` runs every foreground
    /// through `legible`.
    let surfaceStyle = unskinnedSurfaceStyle
    static let unskinnedSurfaceStyle: SkinnedSurfaceStyle = {
        let ground = NSColor(calibratedWhite: 0.14, alpha: 1)
        let text = NSColor(calibratedWhite: 0.8, alpha: 1)
        let selection = SkinnedSurfaceStyle.blend(ground, toward: NSColor(calibratedRed: 0.94, green: 0.49, blue: 0.09, alpha: 1), by: 0.45)
        return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: ground, text: text, currentText: .white, selectionBackground: selection, selectionText: .white,
            treeText: text, treeSelection: selection))
    }()

    /// `importer`: the installed skins and selection; `windowStore`: where each skin's form windows
    /// were left. A test passes its own of each.
    init(importer: AIMPSkinImporter = AIMPSkinImporter(),
         windowStore: SkinWindowStore = SkinWindowStore(defaults: .standard, keys: .aimp)) {
        self.importer = importer
        forms = AIMPSkinFormWindowMaterializer(store: windowStore)
        let window = SkinnedBorderlessWindow(contentRect: NSRect(origin: .zero, size: Self.placeholderSize),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        // Frames are drawn in sRGB; a window in the display's own space was matched to it one way or
        // another from one frame to the next, every colour flickering 10% (Kantaris-Teyp, WMP12 SB).
        window.colorSpace = .sRGB
        // The skin casts its own, from what it draws (`AIMPSkinMainView`).
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.title = "NullPlayer — AIMP"
        window.setAccessibilityIdentifier("AIMPSkinMainWindow")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = skinView
        forms.onContentChange = { [weak self] in self?.updateCompanionVisibility() }
        // A hidden form gives the library browser up, and the windows still showing lists take it back.
        forms.onFormHidden = { [weak self] view in
            guard let self, self.libraryHost.release(from: view) else { return }
            self.skinView.reportLibraryArea()
            self.forms.reportLibraryAreas()
        }
        skinView.onLibraryArea = { [weak self] view, rect, colours in self?.libraryHost.libraryArea(rect, colours: colours, in: view) }
        skinView.extraMenuItems = { [weak self] in self?.companionMenuItems() ?? [] }
        skinView.popupMenu = { [weak self] popup, clickedRow, window in
            guard let self, self.runtime != nil else { return NSMenu() }
            self.playlistMenu.window = window
            return Self.popupMenu(popup, playlist: self.playlistMenu, clickedRow: clickedRow)
        }
        skinView.onDisplaySizeChange = { [weak self] in self?.fitWindow() }
        levelModel.onLevels = { [weak self] left, right in
            guard let self else { return }
            let floor = self.levelModel.floorDB
            self.runtime?.levels = (AIMPSkinAudioEngineHost.meterLevel(left, floor: floor), AIMPSkinAudioEngineHost.meterLevel(right, floor: floor))
        }
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

    /// A runtime for `skin`, wired to the player and to the skin's form windows.
    private func makeRuntime(_ skin: AIMPSkin) -> AIMPSkinRuntime {
        let runtime = AIMPSkinRuntime(skin: skin, player: currentPlayer())
        runtime.onStateChange = { [weak self] in self?.updateCompanionVisibility() }
        // The meters run with the skin's clock: playing, and on screen.
        runtime.onClockChange = { [weak self] running in
            guard let self else { return }
            running ? self.levelModel.start() : self.levelModel.stop()
        }
        runtime.onAction = { [weak self] action in
            self?.engineHost.perform(action, window: self?.window)
            self?.refreshHostState()
        }
        return runtime
    }

    // MARK: - Choosing a skin (`SkinFileMainWindow`)

    var skinSelection: SkinSelection { importer.selection }
    func selectedSkinURL() throws -> URL? { try importer.selectedSkinURL() }
    static func loadSkin(at url: URL) async throws -> AIMPSkin { try await AIMPSkinLoader.load(file: url) }

    func importFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = AIMPSkinImporter.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) } + [.zip]
        panel.message = "Select an AIMP skin (.acs5, .acs4, .acs3, .acs, or a .zip from the AIMP catalog)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        skinLoad.run({ [importer] in try await importer.importSkins(from: url) },
                     done: { [weak self] _ in self?.reloadSelectedSkin() },
                     failed: { error in
                         let alert = NSAlert()
                         alert.messageText = "“\(url.lastPathComponent)” could not be loaded."
                         alert.informativeText = "\(error.localizedDescription)"
                         alert.runModal()
                     })
    }

    // MARK: - Presenting

    func present(_ shown: (skin: AIMPSkin, url: URL)?, error: Error?) {
        if let shown {
            NSLog("AIMPSkin: loaded '%@' (%d findings)", shown.url.lastPathComponent, shown.skin.findings.count)
        }
        if let error { NSLog("AIMPSkin: %@", "\(error)") }
        loadedSkinURL = shown?.url
        skinView.message = error.map { "This AIMP skin could not be loaded:\n\($0.localizedDescription)" }
        // As with `.wal` skins, a skin switch neither opens nor closes the playlist or library: what
        // is open now (the skin's own window, or NullPlayer's for a skin with none) stays open. The
        // first skin up carries NullPlayer's windows as the outgoing mode left them, its own starting
        // closed rather than at each skin's `InitialVisible`; a launch's restored session opens them
        // after it (`deferUntilSkinLoads`). Read through the routed answer, before the outgoing skin
        // stops: its own window where it draws one, else NullPlayer's.
        let carried = Self.lists.filter(Self.isOpen)
        // One skin at a time: the outgoing one stops and its windows go, then the incoming one is
        // installed with its windows, then its load scripts run. Started beside the outgoing
        // windows, its scripts showed and hid those.
        runtime?.stop()
        forms.teardown()
        libraryHost.teardown()
        runtime = shown.map { makeRuntime($0.skin) }
        playlistMenu.runtime = runtime
        skinView.runtime = runtime
        forms.rebuild(shown?.skin, skinName: shown?.url.deletingPathExtension().lastPathComponent, runtime: runtime, like: skinView)
        // The forms the user last left open or closed with this skin, before its load scripts.
        if let runtime { forms.restoreVisibility(of: runtime.skin, into: &runtime.state) }
        updateCompanionVisibility()
        // The skin's load scripts read the player as it is (a theme by Night Mode, a restored track).
        refreshHostState()
        runtime?.start()
        let nativeOpens = carry(carried)
        WindowManager.shared.dismissFallbackSurfacesTheSkinProvides()
        fitWindow()
        // The main window may come on screen after the skin does.
        DispatchQueue.main.async { [weak self] in self?.updateCompanionVisibility() }
        // Up: the opens a launch restored, then NullPlayer's windows the skin draws none of, which
        // now open rather than wait.
        skinPresented = true
        forms.recordsVisibility = runtime != nil
        let opens = opensAwaitingSkin
        opensAwaitingSkin = []
        opens.forEach { $0() }
        for surface in nativeOpens { surface == .playlist ? WindowManager.shared.showPlaylist() : WindowManager.shared.showMediaLibrary() }
    }

    // MARK: - Form windows

    /// Shows the forms the skin's state has visible (a key, a script, the menu) and hides the rest.
    private func updateCompanionVisibility() {
        guard let flow = runtime?.flow, let main = window else { return }
        forms.update(flow, deck: main)
    }

    // MARK: - The skin's own playlist and library (`SkinSurfaceRouter`)

    /// The surfaces an AIMP skin may draw its own of. Its equalizer is one of its forms, never a
    /// stand-in: NullPlayer's EQ window serves beside every skin.
    private static let lists: [SkinSurface] = [.playlist, .library]

    /// Whether `surface` is open as `WindowManager` answers it: the skin's own form where it draws
    /// one, else NullPlayer's window.
    private static func isOpen(_ surface: SkinSurface) -> Bool {
        surface == .playlist ? WindowManager.shared.isPlaylistVisible : WindowManager.shared.isPlexBrowserVisible
    }

    /// Opens the incoming skin's playlist and library forms that are in `open` and closes the rest.
    /// Returns the surfaces in `open` the skin draws none of and NullPlayer's window does not show
    /// yet, to open once the skin is up. NullPlayer's windows beside the skin's own are closed after
    /// (`dismissFallbackSurfacesTheSkinProvides`).
    /// With no skin (one that failed to load), every surface open is NullPlayer's to open.
    private func carry(_ open: [SkinSurface]) -> [SkinSurface] {
        var state = runtime?.state
        var nativeOpens: [SkinSurface] = []
        for surface in Self.lists {
            let own = ownForms(surface)
            if own.isEmpty {
                if open.contains(surface), !Self.isOpen(surface) { nativeOpens.append(surface) }
                continue
            }
            for form in own { state?.script[form.name].visible = open.contains(surface) }
        }
        if let state { runtime?.state = state }
        return nativeOpens
    }

    /// The skin's forms standing for NullPlayer's `surface`, docked or in a window of their own.
    private func ownForms(_ surface: SkinSurface) -> [AIMPSkin.Companion] {
        switch surface {
        case .playlist: return runtime?.skin.companions(.playlist) ?? []
        case .library: return runtime?.skin.companions(.library) ?? []
        case .equalizer, .video: return []
        }
    }

    func drawsSurface(_ surface: SkinSurface) -> Bool { !ownForms(surface).isEmpty }

    /// Whether the skin's state shows one of its forms for `surface`: in its window, or in its dock
    /// site on the deck.
    func isShowingSurface(_ surface: SkinSurface) -> Bool {
        guard let flow = runtime?.flow else { return false }
        return ownForms(surface).contains { flow.isVisible($0.name) }
    }

    /// A show or toggle of the skin's own forms. Where a form's window opens is the skin's and the
    /// user's (`AIMPSkinFormWindowMaterializer`), so `restoredFrame` is not used.
    func revealSurface(_ surface: SkinSurface, toggle: Bool, restoredFrame: NSRect?) {
        guard var state = runtime?.state else { return }
        let open = toggle ? !isShowingSurface(surface) : true
        for form in ownForms(surface) { state.script[form.name].visible = open }
        runtime?.state = state
    }

    /// A playlist or library show waits for the first skin: until it is up, nothing says whether the
    /// skin draws its own (a launch restores the playlist before the skin has loaded), so NullPlayer's
    /// would open and then close again. The equalizer is always NullPlayer's.
    func deferUntilSkinLoads(_ surface: SkinSurface, _ open: @escaping () -> Void) -> Bool {
        guard Self.lists.contains(surface), !skinPresented else { return false }
        opensAwaitingSkin.append(open)
        return true
    }

    /// The companion windows, checked while shown, for the context menu (AIMP lists them in its own).
    private func companionMenuItems() -> [NSMenuItem] {
        guard let runtime else { return [] }
        return forms.menuItems(runtime.flow) { [weak runtime] name, visible in runtime?.state.script[name].visible = visible }
    }

    func applyUIScale(_ scale: CGFloat) {
        let scale = max(0.1, scale)
        skinView.uiScale = scale
        fitWindow()
        forms.apply(scale: scale)
    }

    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        let size = skinView.displaySize
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    /// Sizes the window to the form at the current scale, holding its top-left corner. The windows
    /// docked under the deck move with its bottom edge (GX-F90's AMP key grows the deck over the
    /// playlist under it).
    private func fitWindow() {
        guard let window else { return }
        let old = window.frame
        AIMPSkinFormWindowMaterializer.fit(window, to: skinView)
        WindowManager.shared.carryWindowsDockedBelow(window, from: old)
    }

    /// The skin's form windows made so far, which `WindowManager` docks, raises and re-places
    /// (`SkinOwnedWindowsProviding`).
    var skinOwnedWindows: [NSWindow] { forms.materializedAuxiliaryWindows }

    // MARK: - Host state

    private func refreshHostState() {
        runtime?.update(player: currentPlayer())
    }

    /// The player now, with the playing track's artwork.
    private func currentPlayer() -> AIMPSkinPlayerSnapshot {
        engineHost.refreshPlaylist()
        var player = engineHost.snapshot()
        player.coverArt = coverArt
        player.waveform = waveform
        return player
    }

    func updateTrackInfo(_ track: Track?) {
        engineHost.playbackDidChange()
        // A track's tags and duration can arrive after it was queued, under the same id.
        engineHost.playlistChanged()
        updateArtwork(for: track)
        refreshHostState()
    }

    /// The playing track's artwork, for the skin's cover-art displays, loaded once per track.
    private func updateArtwork(for track: Track?) {
        guard artworkTrackID != track?.id else { return }
        artworkTrackID = track?.id
        artworkTask?.cancel()
        coverArt = nil
        updateWaveform(for: track)
        guard let track else { return refreshHostState() }
        artworkTask = Task { [weak self] in
            let image = await TrackArtworkLoader.loadArtwork(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackID == track.id else { return }
            self.coverArt = image
            self.refreshHostState()
        }
    }
    /// The playing track's waveform, worked out (or read from its cache) once per track by NullPlayer's
    /// waveform service, peaks kept per 512 columns; none for a stream.
    private func updateWaveform(for track: Track?) {
        waveformTask?.cancel()
        waveform = []
        guard let track else { return }
        waveformTask = Task { [weak self] in
            let snapshot = await WaveformCacheService.shared.loadSnapshot(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackID == track.id, snapshot.state == .ready, !snapshot.samples.isEmpty else { return }
            self.waveform = WaveformDrawing.makeColumnAmplitudes(samples: snapshot.samples, pixelWidth: 512)
            self.refreshHostState()
        }
    }

    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() {
        engineHost.playbackDidChange()
        refreshHostState()
    }

    /// The playlist changed (added to, sorted, a row taken out): the skin's own list follows.
    /// A burst of playlist changes (a restore swaps thousands of streaming placeholders in one by
    /// one) refreshes once, after it.
    func playlistContentDidChange() {
        engineHost.playlistChanged()
        guard !playlistRefreshPending else { return }
        playlistRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.playlistRefreshPending = false
            self?.refreshHostState()
        }
    }

    /// Show Artist / Show Album changed: the rows' text follows.
    func playlistMarkersDidChange() {
        engineHost.playlistChanged()
        refreshHostState()
    }

    func updateSpectrum(_ levels: [Float]) { runtime?.spectrum = levels.map { Double($0) } }

    func skinDidChange() {}
    func windowVisibilityDidChange() {
        runtime?.updateClock()
        refreshHostState()
        updateCompanionVisibility()
    }

    func prepareForUITeardown() {
        runtime?.stop()
        engineHost.stop()
        forms.teardown()
        libraryHost.teardown()
        levelModel.stop()
        skinLoad.cancel()
        artworkTask?.cancel()
        waveformTask?.cancel()
    }

    // MARK: - Window delegate

    func windowDidChangeOcclusionState(_ notification: Notification) {
        runtime?.updateClock()
        updateCompanionVisibility()
    }

    /// The deck's own moves; the form windows' go to `AIMPSkinFormWindowMaterializer`.
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        WindowManager.shared.applySnappedPosition(window, to: WindowManager.shared.windowWillMove(window, to: window.frame.origin))
    }
}
