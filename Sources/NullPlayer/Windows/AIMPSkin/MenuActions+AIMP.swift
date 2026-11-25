import AppKit

// MARK: - AIMP skins actions

extension AIMPSkinMainWindowController {
    static let mode = PlayerUIMode.aimp
    static let feature = AppFeature.aimpSkinMode
    static func importer() -> AIMPSkinImporter { AIMPSkinImporter() }
}

/// The Skins menu's AIMP entries; all but Get More are `SkinFileMainWindow`'s.
@MainActor
extension MenuActions {
    @objc func setAIMPMode() { AIMPSkinMainWindowController.switchToFamily() }

    @objc func selectAIMPSkin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        AIMPSkinMainWindowController.chooseSkin(named: name)
    }

    @objc func loadAIMPSkinFromFile() { AIMPSkinMainWindowController.loadSkinFromFile() }

    @objc func getMoreAIMPSkins() {
        guard let url = URL(string: "https://www.aimp.ru/?do=catalog&os=windows&type=skins") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openAIMPSkinsFolder() { AIMPSkinMainWindowController.openSkinsFolder() }

    func removeAIMPSkin(named name: String) { AIMPSkinMainWindowController.removeInstalledSkin(named: name) }
}
