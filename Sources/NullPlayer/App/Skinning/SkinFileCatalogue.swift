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
    func installedSkins() -> [InstalledSkinFile] {
        Self.skinFilesByName(in: folder).compactMap { name, files in files.first.map { InstalledSkinFile(name: name, url: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        for file in Self.skinFilesByName(in: folder)[skin.name] ?? [] { try await folder.remove(file) }
        selection.forget(name)
    }

    /// Installs `file` under its own name, replacing the skin of that name, once `validate` passes the
    /// copy being committed. Its extension is kept when it is one of the family's, else the first.
    /// Selecting it is the caller's.
    static func install(_ file: URL, into folder: SkinInstallFolder,
                        validate: (URL) async throws -> Void) async throws -> InstalledSkinFile {
        let skin = destination(of: file, in: folder)
        try await folder.commit(file, to: skin.url, suffix: "." + skin.url.pathExtension, validate: validate)
        for other in otherFiles(of: skin, in: folder) { try? await folder.remove(other) }
        return skin
    }

    /// `install` for several files at once, all or none (a zip's skins): each copy committed is
    /// validated, and none replaces an installed skin until every one has passed. Of several files
    /// with one skin name (`Theme.acs4`, `Theme.acs5`), the first is the skin and the rest are left
    /// out, so the cleanup of one cannot delete another.
    static func installAll(_ files: [URL], into folder: SkinInstallFolder,
                           validate: (URL) async throws -> Void) async throws -> [InstalledSkinFile] {
        var names = Set<String>()
        // Without regard to case: on a case-insensitive volume `Theme.acs4` and `theme.acs4` are one file.
        let files = files.filter { names.insert($0.deletingPathExtension().lastPathComponent.lowercased()).inserted }
        let skins = files.map { destination(of: $0, in: folder) }
        try await folder.commitAll(zip(files, skins).map { ($0, $1.url, "." + $1.url.pathExtension) }, validate: validate)
        for skin in skins {
            for other in otherFiles(of: skin, in: folder) { try? await folder.remove(other) }
        }
        return skins
    }

    /// Where `file` installs: under its own name, with its extension when that is one of the
    /// family's, else the first.
    private static func destination(of file: URL, in folder: SkinInstallFolder) -> InstalledSkinFile {
        let name = file.deletingPathExtension().lastPathComponent
        let own = file.pathExtension.lowercased()
        let ext = fileExtensions.contains(own) ? own : fileExtensions[0]
        return InstalledSkinFile(name: name, url: folder.url.appendingPathComponent("\(name).\(ext)"))
    }

    /// The files of an installed skin's name other than its own, which go so the name stays one
    /// skin. The skin is installed by then, and its extension may not be the preferred one, so a
    /// file that will not go is left rather than failing the install.
    private static func otherFiles(of skin: InstalledSkinFile, in folder: SkinInstallFolder) -> [URL] {
        (skinFilesByName(in: folder)[skin.name] ?? []).filter { !isSameFile($0, skin.url) }
    }

    /// Whether `a` and `b` are one file on disk: on a case-insensitive volume `Deck.SGF` and
    /// `Deck.sgf` are, and the skin just installed under one must not be removed as the other.
    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        if a.lastPathComponent == b.lastPathComponent { return true }
        let key = URLResourceKey.fileResourceIdentifierKey
        guard let first = (try? a.resourceValues(forKeys: [key]))?.fileResourceIdentifier,
              let second = (try? b.resourceValues(forKeys: [key]))?.fileResourceIdentifier else { return false }
        return first.isEqual(second)
    }

    /// The visible skin files in `folder` by skin name, each name's in `fileExtensions` order.
    private static func skinFilesByName(in folder: SkinInstallFolder) -> [String: [URL]] {
        var ranked: [String: [(rank: Int, url: URL)]] = [:]
        for file in (try? folder.fileManager.contentsOfDirectory(atPath: folder.url.path)) ?? [] where !file.hasPrefix(".") {
            let url = folder.url.appendingPathComponent(file)
            guard let rank = fileExtensions.firstIndex(of: url.pathExtension.lowercased()) else { continue }
            ranked[url.deletingPathExtension().lastPathComponent, default: []].append((rank, url))
        }
        return ranked.mapValues { $0.sorted { $0.rank < $1.rank }.map(\.url) }
    }
}
