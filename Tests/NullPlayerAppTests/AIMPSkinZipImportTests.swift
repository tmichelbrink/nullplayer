import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// A `.zip` of AIMP skins (`AIMPSkinImporter.unzipSkins`): bounded from its central directory before
/// anything is written, each skin held to its size and CRC, and a name taken once.
final class AIMPSkinZipImportTests: XCTestCase {
    func testOnlySkinsAreTakenAndANameOnce() throws {
        let files = try unzip([
            WMPTestArchiveEntry("A/Deck.acs4", data: Data("first".utf8)),
            WMPTestArchiveEntry("B/deck.acs5", data: Data("second".utf8)),
            WMPTestArchiveEntry("Other.acs", data: Data("other".utf8)),
            WMPTestArchiveEntry("readme.txt", data: Data("text".utf8)),
            WMPTestArchiveEntry("__MACOSX/A/._Deck.acs4", data: Data("junk".utf8)),
        ])
        XCTAssertEqual(files.map(\.lastPathComponent), ["Deck.acs4", "Other.acs"], "a second Deck, in another folder or extension, is not written over the first")
        XCTAssertEqual(try Data(contentsOf: files[0]), Data("first".utf8))
    }

    func testBoundsAreCheckedBeforeAnythingIsWritten() throws {
        let entries = [WMPTestArchiveEntry("One.acs4", data: Data(count: 100)), WMPTestArchiveEntry("Two.acs4", data: Data(count: 100))]
        var few = SkinZipLimits.aimpSkins
        few.entries = 1
        var small = SkinZipLimits.aimpSkins
        small.entryBytes = 99
        var tight = SkinZipLimits.aimpSkins
        tight.totalBytes = 150
        for (limits, code) in [(few, AIMPSkinDiagnosticCode.zipRejected), (small, .fileTooLarge), (tight, .zipRejected)] {
            let directory = try WMPSkinTestSupport.temporaryDirectory()
            XCTAssertEqual(try failure(entries, limits: limits, into: directory), code)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [], "a rejected zip writes nothing")
        }
    }

    /// Skins are compressed already: past the 1 MiB floor, a skin that squashes past 200:1 is a bomb.
    func testARatioPastItsFloorIsABomb() throws {
        XCTAssertNil(try failure([WMPTestArchiveEntry("Plain.acs4", data: Data(count: 64 * 1_024), compression: .deflate)]))
        XCTAssertEqual(try failure([WMPTestArchiveEntry("Bomb.acs4", data: Data(count: 2 * 1_024 * 1_024), compression: .deflate)]),
                       .zipRejected)
    }

    func testASkinThatFailsItsCRCIsRefused() throws {
        let payload = Data("a skin's bytes, stored".utf8)
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("Deck.acs4", data: payload)], filename: "skins.zip")
        var zip = try Data(contentsOf: url)
        let at = try XCTUnwrap(zip.range(of: payload)).lowerBound
        zip[at] ^= 0xFF
        try zip.write(to: url)
        XCTAssertEqual(try failure(url, limits: .aimpSkins), .zipRejected)
    }

    // MARK: - Helpers

    private func unzip(_ entries: [WMPTestArchiveEntry], limits: SkinZipLimits = .aimpSkins) throws -> [URL] {
        let url = try WMPSkinTestSupport.makeArchive(entries, filename: "skins.zip")
        return try AIMPSkinImporter.unzipSkins(url, into: try WMPSkinTestSupport.temporaryDirectory(), limits: limits)
    }

    /// The finding's code; an error that is not a finding is rethrown, never read as success.
    /// `directory`: where the skins are written, a fresh folder when nil.
    private func failure(_ entries: [WMPTestArchiveEntry], limits: SkinZipLimits = .aimpSkins,
                         into directory: URL? = nil) throws -> AIMPSkinDiagnosticCode? {
        try failure(try WMPSkinTestSupport.makeArchive(entries, filename: "skins.zip"), limits: limits, into: directory)
    }

    private func failure(_ url: URL, limits: SkinZipLimits, into directory: URL? = nil) throws -> AIMPSkinDiagnosticCode? {
        do {
            _ = try AIMPSkinImporter.unzipSkins(url, into: try directory ?? WMPSkinTestSupport.temporaryDirectory(), limits: limits)
            return nil
        } catch let finding as AIMPSkinFinding {
            return finding.code
        }
    }
}
