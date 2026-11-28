import Foundation
import XCTest
@testable import NullPlayer

/// A corpus skin a test reads by file name: from `AIMP_TEST_SKINS` when set, else the installed
/// skins (`Application Support/NullPlayer/AIMPSkins`); the test is skipped when neither has it.
enum AIMPCorpusSkin {
    static func load(_ name: String) throws -> AIMPSkin {
        let dirs: [String?] = [ProcessInfo.processInfo.environment["AIMP_TEST_SKINS"],
                               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NullPlayer/AIMPSkins").path]
        guard let file = dirs.compactMap({ $0 }).map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("\(name) is not installed") }
        return try AIMPSkinLoader.load(contentsOf: file)
    }
}
