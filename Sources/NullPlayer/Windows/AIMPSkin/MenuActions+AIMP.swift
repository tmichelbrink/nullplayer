import AppKit

// MARK: - AIMP skins actions

extension SkinFileFamilyActions where Controller == AIMPSkinMainWindowController {
    static var aimp: Self {
        Self(mode: .aimp, feature: .aimpSkinMode,
             selection: { AIMPSkinImporter().selection },
             folder: { AIMPSkinImporter().folder },
             removeInstalled: { try await AIMPSkinImporter().removeSkin(named: $0) },
             importFromPanel: { $0.importSkinFromPanel() })
    }
}

/// The Skins menu's AIMP entries; all but Get More are `SkinFileFamilyActions`.
extension MenuActions {
    @objc func setAIMPMode() { SkinFileFamilyActions.aimp.switchToFamily() }

    @objc func selectAIMPSkin(_ sender: NSMenuItem) { SkinFileFamilyActions.aimp.select(sender) }

    @objc func loadAIMPSkinFromFile() { SkinFileFamilyActions.aimp.loadFromFile() }

    @objc func getMoreAIMPSkins() {
        guard let url = URL(string: "https://www.aimp.ru/?do=catalog&os=windows&type=skins") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openAIMPSkinsFolder() { SkinFileFamilyActions.aimp.openFolder() }

    func removeAIMPSkin(named name: String) { SkinFileFamilyActions.aimp.remove(named: name) }
}
