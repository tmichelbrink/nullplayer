import Foundation
import ZIPFoundation

enum AIMPSkinImportError: LocalizedError {
    case noSkinInZip(String)

    var errorDescription: String? {
        switch self {
        case let .noSkinInZip(name):
            return "“\(name)” holds no .acs5, .acs4, .acs3 or .acs skin."
        }
    }
}

/// The installed-skins folder and the selection preference (`SkinFileCatalogue`). A skin is one
/// `.acs5`, `.acs4`, `.acs3` or `.acs` file, validated through `AIMPSkinLoader` off the main thread as
/// it is committed (`SkinInstallFolder`); of two files with one name, the first of `fileExtensions`
/// is the skin. The AIMP catalog ships each skin in a `.zip`; importing one installs every skin
/// inside it.
struct AIMPSkinImporter: SkinFileCatalogue {
    static let family = "AIMP"
    static let fileExtensions = ["acs5", "acs4", "acs3", "acs"]

    let folder: SkinInstallFolder
    let selection: SkinSelection

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        selection = SkinSelection(key: "aimpSkinName", defaults: defaults)
        folder = SkinInstallFolder("AIMPSkins", at: directoryURL, fileManager: fileManager)
    }

    /// Installs an `.acs5`/`.acs4`, or every one inside a `.zip`, replacing any of the same name, and
    /// selects the first.
    @discardableResult
    func importSkins(from source: URL) async throws -> [InstalledSkinFile] {
        let installed = try await Task.detached(priority: .userInitiated) { [folder] in
            guard source.pathExtension.lowercased() == "zip" else { return [try await Self.install(source, into: folder)] }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            // Every skin of the zip loads, as the copy being committed, before any is installed: one
            // that does not leaves the installed skins as they were, not some of them replaced.
            let files = try Self.unzipSkins(source, into: staging)
            let skins = try await Self.installAll(files, into: folder) { url in _ = try await AIMPSkinLoader.load(file: url) }
            guard !skins.isEmpty else { throw AIMPSkinImportError.noSkinInZip(source.lastPathComponent) }
            return skins
        }.value
        if let first = installed.first { selection.select(first.name) }
        return installed
    }

    private static func install(_ file: URL, into folder: SkinInstallFolder) async throws -> InstalledSkinFile {
        try await install(file, into: folder) { url in _ = try await AIMPSkinLoader.load(file: url) }
    }

    /// The skins of a zip, flattened into `directory` by file name, through `SkinZipExtraction` with
    /// AIMP's limits. A name is one skin, whatever its extension or folder in the zip: the first entry
    /// of a name is taken, so no skin is written, or installed, twice. A bound past `entryBytes` is
    /// `AM0002`, any other rejection `AM0012`. Off the main thread; a zip that fails a check part-way
    /// can leave files in `directory`, which the caller discards.
    static func unzipSkins(_ zip: URL, into directory: URL, limits: SkinZipLimits = .aimpSkins) throws -> [URL] {
        let archive = try Archive(url: zip, accessMode: .read)
        var names = Set<String>()
        do {
            return try SkinZipExtraction.extract(archive, limits: limits) { entry in
                let name = (entry.path as NSString).lastPathComponent
                let stem = (name as NSString).deletingPathExtension.lowercased()
                guard entry.type == .file, !name.hasPrefix("."), fileExtensions.contains((name as NSString).pathExtension.lowercased()),
                      names.insert(stem).inserted else { return nil }
                return directory.appendingPathComponent(name)
            }
        } catch let rejection as SkinZipExtraction.Rejection {
            throw try finding(rejection)
        }
    }

    /// AIMP's finding for a rejected zip; a failure that is not a bound is rethrown as it came.
    private static func finding(_ rejection: SkinZipExtraction.Rejection) throws -> AIMPSkinFinding {
        switch rejection {
        case let .tooManyEntries(limit):
            return AIMPSkinFinding(.zipRejected, "More than \(limit) entries.")
        case let .entryTooLarge(path, bytes, limit):
            return AIMPSkinFinding(.fileTooLarge, "'\(path)' expands to \(bytes) bytes, more than \(limit).")
        case let .totalTooLarge(limit):
            return AIMPSkinFinding(.zipRejected, "The zip's skins expand past \(limit) bytes.")
        case let .compressionRatio(path, ratio, limit):
            return AIMPSkinFinding(.zipRejected, "'\(path)' expands \(ratio):1, past \(limit):1.")
        case let .inflatesPastDeclaredSize(path):
            return AIMPSkinFinding(.fileTooLarge, "'\(path)' inflates past its declared size.")
        case let .failsCRCOrSize(path):
            return AIMPSkinFinding(.zipRejected, "'\(path)' fails its CRC or size check.")
        case let .unpackFailed(_, underlying):
            throw underlying
        }
    }
}
