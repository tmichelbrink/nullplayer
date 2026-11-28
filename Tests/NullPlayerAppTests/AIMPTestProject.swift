import Foundation
import XCTest

/// AIMP project files (`ACSJ`, `.acs4proj`) the AIMP tests build their skins from, and the byte
/// helpers they are written with: one encoder, rather than a copy per test class.
enum AIMPTestProject {
    /// `value` as four little-endian bytes (a value past `UInt32` cut to its low bits).
    static func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { Data($0) } }

    /// `text` as AIMP writes a name: a `u16` count of UTF-16 units, then the units, little-endian.
    static func utf16LE(_ text: String) -> Data {
        Data([UInt8(text.utf16.count & 0xFF), UInt8(text.utf16.count >> 8)]) + (text.data(using: .utf16LittleEndian) ?? Data())
    }

    /// A project file of `entries`: the header (13 bytes), the metadata block (u32 length: name
    /// "Test", author, about, no preview), the entry count (`count` when given) and the entries.
    static func data(_ entries: [(String, Data)], count: Int? = nil) -> Data {
        let meta = utf16LE("Test") + utf16LE("") + utf16LE("") + [0]
        var data = Data("ACSJ".utf8) + Data(count: 9) + u32(meta.count) + meta + u32(count ?? entries.count)
        for (name, bytes) in entries { data += utf16LE(name) + u32(bytes.count) + bytes }
        return data
    }

    /// A project file of text `entries`.
    static func data(_ entries: [(String, String)]) -> Data { data(entries.map { ($0, Data($1.utf8)) }) }
}

extension XCTestCase {
    /// A defaults domain of this test's own, removed when the test ends.
    func scopedDefaults() -> UserDefaults {
        let suite = "\(type(of: self))-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite) ?? .standard
    }
}
