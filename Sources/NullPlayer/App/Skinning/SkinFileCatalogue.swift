import Foundation

/// An installed skin of a family whose skin is one file.
struct InstalledSkinFile: Hashable {
    /// The file name without its extension.
    let name: String
    let url: URL
}

enum SkinFileCatalogueError: LocalizedError {
    case selectionMissing(family: String, name: String)
    case notInstalled(family: String, name: String)

    var errorDescription: String? {
        switch self {
        case let .selectionMissing(family, name):
            return "The selected \(family) skin “\(name)” is no longer installed. Load it again or choose another skin."
        case let .notInstalled(family, name):
            return "No \(family) skin named “\(name)” is installed."
        }
    }
}

/// A family whose skin is one file (Sonique's `.sgf`): its installed-skins folder, by name, and the
/// selection preference. A name is one skin, whatever its extension: of two files with one name, the
/// first of `fileExtensions` is the skin, removing the skin removes both, and installing one under
/// another extension replaces the skin of that name. The family keeps its own loader check and naming
/// of what it imports; `install` commits one file through `SkinInstallFolder`. Its `folder`,
/// `selection` and `removeSkin(named:)` are what the Skins menu asks of it (`SkinFileImporting`).
protocol SkinFileCatalogue: SkinFileImporting {
    /// The family as its messages name it ("Sonique").
    static var family: String { get }
    /// A skin file's extensions, lowercased, the one a name prefers first.
    static var fileExtensions: [String] { get }
}

extension SkinFileCatalogue {
    var directoryURL: URL { folder.url }

    func installedSkins() -> [InstalledSkinFile] {
        var skins: [InstalledSkinFile] = []
        var taken: [String: Int] = [:]
        for file in Self.skinFiles(in: folder) {
            let skin = InstalledSkinFile(name: file.deletingPathExtension().lastPathComponent, url: file)
            guard let index = taken[skin.name] else {
                taken[skin.name] = skins.count
                skins.append(skin)
                continue
            }
            if Self.rank(file) ?? 0 < Self.rank(skins[index].url) ?? 0 { skins[index] = skin }
        }
        return skins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed skin of that name; a name that is not a plain visible file name never resolves
    /// outside the directory.
    func skin(named name: String) -> InstalledSkinFile? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return installedSkins().first { $0.name == name }
    }

    /// The selected skin's file, nil when nothing is selected; throws when the selection is gone.
    func selectedSkinURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let skin = skin(named: name) else { throw SkinFileCatalogueError.selectionMissing(family: Self.family, name: name) }
        return skin.url
    }

    /// Deletes an installed skin, every file of its name, off the main thread; removing the selected
    /// one clears the selection.
    func removeSkin(named name: String) async throws {
        guard let skin = skin(named: name) else { throw SkinFileCatalogueError.notInstalled(family: Self.family, name: name) }
        for file in Self.files(named: skin.name, in: folder) { try await folder.remove(file) }
        selection.forget(name)
    }

    /// Installs `file` under its own name, replacing the skin of that name, once `validate` passes the
    /// copy being committed. Its extension is kept when it is one of the family's, else the first.
    /// Selecting it is the caller's.
    static func install(_ file: URL, into folder: SkinInstallFolder,
                        validate: (URL) async throws -> Void) async throws -> InstalledSkinFile {
        let name = file.deletingPathExtension().lastPathComponent
        let own = file.pathExtension.lowercased()
        let ext = fileExtensions.contains(own) ? own : fileExtensions[0]
        let destination = folder.url.appendingPathComponent("\(name).\(ext)")
        try await folder.commit(file, to: destination, suffix: ".\(ext)", validate: validate)
        // The other files of its name go, so the name stays one skin.
        for other in files(named: name, in: folder) where other.lastPathComponent != destination.lastPathComponent {
            try folder.fileManager.removeItem(at: other)
        }
        return InstalledSkinFile(name: name, url: destination)
    }

    /// The visible files in `folder` with one of the family's extensions.
    private static func skinFiles(in folder: SkinInstallFolder) -> [URL] {
        let names = (try? folder.fileManager.contentsOfDirectory(atPath: folder.url.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && rank(URL(fileURLWithPath: $0)) != nil }
            .map { folder.url.appendingPathComponent($0) }
    }

    /// The files in `folder` that are the skin `name`, under any of the extensions.
    private static func files(named name: String, in folder: SkinInstallFolder) -> [URL] {
        skinFiles(in: folder).filter { $0.deletingPathExtension().lastPathComponent == name }
    }

    /// Where a file's extension stands in `fileExtensions`; nil for a file that is no skin.
    private static func rank(_ file: URL) -> Int? {
        fileExtensions.firstIndex(of: file.pathExtension.lowercased())
    }
}
