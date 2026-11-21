import AppKit

/// What the Skins menu does for a family whose skins are installed by name and loaded by a
/// `SkinFileMainWindow` (Audion, Sonique): switch to it, choose an installed skin, load one from a
/// file, open its folder, remove one. The actions are the same for each family; it names its mode,
/// feature, store and window. Each family's `MenuActions` entry points call these, so its menu keeps
/// its own selectors.
struct SkinFileFamilyActions<Controller: SkinFileMainWindow> {
    let mode: PlayerUIMode
    let feature: AppFeature
    /// The family's saved choice.
    let selection: () -> SkinSelection
    /// The family's installed-skins folder.
    let folder: () -> SkinInstallFolder
    /// Deletes the installed skin of that name, clearing the selection if it was that one.
    let removeInstalled: (String) async throws -> Void
    /// The window's own import panel.
    let importFromPanel: (Controller) -> Void

    private var controller: Controller? { WindowManager.shared.mainWindowController as? Controller }

    func switchToFamily() {
        guard AppCapabilities.supports(feature), WindowManager.shared.uiMode != mode else { return }
        WindowManager.shared.reloadUI(to: mode)
    }

    /// In place inside the family; otherwise the selection is saved and entering the family loads it.
    func select(_ sender: NSMenuItem) {
        guard AppCapabilities.supports(feature), let name = sender.representedObject as? String else { return }
        if let controller {
            controller.selectSkin(named: name)
        } else {
            selection().select(name)
            WindowManager.shared.reloadUI(to: mode)
        }
    }

    func loadFromFile() {
        guard AppCapabilities.supports(feature) else { return }
        if let controller {
            importFromPanel(controller)
        } else {
            WindowManager.shared.reloadUI(to: mode) { self.controller.map(importFromPanel) }
        }
    }

    func openFolder() {
        do {
            let folder = folder()
            try folder.ensureExists()
            NSWorkspace.shared.open(folder.url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func remove(named name: String) {
        Task { @MainActor in
            do {
                try await removeInstalled(name)
                controller?.resetToUnskinned()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

extension SkinFileFamilyActions where Controller == SoniqueSkinMainWindowController {
    static var sonique: Self {
        Self(mode: .sonique, feature: .soniqueSkinMode,
             selection: { SoniqueSkinImporter().selection },
             folder: { SoniqueSkinImporter().folder },
             removeInstalled: { try await SoniqueSkinImporter().removeSkin(named: $0) },
             importFromPanel: { $0.importSkinFromPanel() })
    }
}

extension SkinFileFamilyActions where Controller == AudionFaceMainWindowController {
    static var audion: Self {
        Self(mode: .audion, feature: .audionFaceMode,
             selection: { AudionFaceImporter().selection },
             folder: { AudionFaceImporter().folder },
             removeInstalled: { try await AudionFaceImporter().removeFace(named: $0) },
             importFromPanel: { $0.importFaceFromPanel() })
    }
}
