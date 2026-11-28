import XCTest
@testable import NullPlayer

/// A one-file-per-skin family's installed skins (`SkinFileCatalogue`): what the selection resolves to,
/// the errors' wording, and that a name is one skin across the family's extensions.
final class SkinFileCatalogueTests: XCTestCase {
    /// A family of two extensions, the first preferred.
    private struct Catalogue: SkinFileCatalogue {
        static let family = "Test"
        static let fileExtensions = ["new", "old"]
        let folder: SkinInstallFolder
        let selection: SkinSelection
    }

    private var folder: URL!
    private var catalogue: Catalogue!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("skin-catalogue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SkinFileCatalogueTests-\(UUID().uuidString)"))
        catalogue = Catalogue(folder: SkinInstallFolder("unused", at: folder), selection: SkinSelection(key: "skin", defaults: defaults))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ names: String...) throws {
        for name in names { try Data("x".utf8).write(to: folder.appendingPathComponent(name)) }
    }

    private var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func testAMissingSelectionAndAnUnknownRemovalNameTheFamily() async throws {
        catalogue.selection.select("Gone")
        XCTAssertThrowsError(try catalogue.selectedSkinURL()) { error in
            XCTAssertEqual(error.localizedDescription,
                           "The selected Test skin “Gone” is no longer installed. Load it again or choose another skin.")
        }
        do {
            try await catalogue.removeSkin(named: "Gone")
            XCTFail("removed nothing")
        } catch {
            XCTAssertEqual(error.localizedDescription, "No Test skin named “Gone” is installed.")
        }
    }

    func testANameIsOneSkinAcrossExtensions() async throws {
        try touch("Deck.old", "Deck.NEW", "Other.old", ".hidden.new", "notes.txt")
        XCTAssertEqual(catalogue.installedSkins().map(\.name), ["Deck", "Other"])
        XCTAssertNil(catalogue.skin(named: "../Deck"))
        catalogue.selection.select("Deck")
        XCTAssertEqual(try catalogue.selectedSkinURL()?.lastPathComponent, "Deck.NEW")
        try await catalogue.removeSkin(named: "Deck")
        XCTAssertEqual(files, ["Other.old", "notes.txt"])
        XCTAssertNil(catalogue.selection.name)
    }

    func testInstallingUnderAnotherExtensionReplacesTheSkinAndAForeignOneTakesTheFirst() async throws {
        try touch("Deck.new")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("skin-catalogue-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        for name in ["Deck.OLD", "Plain.bin"] { try Data("y".utf8).write(to: source.appendingPathComponent(name)) }

        var validated: [String] = []
        let deck = try await Catalogue.install(source.appendingPathComponent("Deck.OLD"), into: catalogue.folder) {
            validated.append($0.pathExtension)
        }
        XCTAssertEqual(deck.url.lastPathComponent, "Deck.old")
        _ = try await Catalogue.install(source.appendingPathComponent("Plain.bin"), into: catalogue.folder) { _ in }
        XCTAssertEqual(files, ["Deck.old", "Plain.new"])
        XCTAssertEqual(validated, ["old"], "the copy validated carries the extension a loader may read")
        XCTAssertNil(catalogue.selection.name, "selecting is the caller's")
    }

    /// Two files of one skin name in a batch, in any case, install as one skin, the first: the
    /// cleanup of one must not delete the other.
    func testInstallAllTakesTheFirstFileOfAName() async throws {
        let source = folder.deletingLastPathComponent().appendingPathComponent("src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let first = source.appendingPathComponent("Theme.\(Catalogue.fileExtensions[1])")
        let second = source.appendingPathComponent("Theme.\(Catalogue.fileExtensions[0])")
        let other = source.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let third = other.appendingPathComponent("theme.\(Catalogue.fileExtensions[1])")
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)
        try Data("3".utf8).write(to: third)
        let skins = try await Catalogue.installAll([first, second, third], into: catalogue.folder) { _ in }
        XCTAssertEqual(skins.map(\.name), ["Theme"])
        XCTAssertEqual(files, [first.lastPathComponent])
        XCTAssertEqual(try String(contentsOf: skins[0].url, encoding: .utf8), "1")
    }

    /// A skin installed over a file of its name in another case (`Deck.NEW`, put there by hand) is
    /// kept: on a case-insensitive disk the two are one file, which the cleanup must not delete.
    func testInstallingOverAnotherCaseKeepsTheSkin() async throws {
        try Data("old".utf8).write(to: folder.appendingPathComponent("Deck.NEW"))
        let source = folder.deletingLastPathComponent().appendingPathComponent("src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Deck.new")
        try Data("new".utf8).write(to: file)
        let skin = try await Catalogue.install(file, into: catalogue.folder) { _ in }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try String(contentsOf: skin.url, encoding: .utf8), "new", "the installed skin is still there")
        XCTAssertEqual(catalogue.installedSkins().map(\.name), ["Deck"])
    }
}
