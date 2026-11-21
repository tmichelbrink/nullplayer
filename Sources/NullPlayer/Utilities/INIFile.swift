import Foundation

/// A Windows INI file: `[Section]` headers over `key=value` lines, as skins write them (Sonique's
/// `skin.ini`). Sections and keys are found without regard to case, the first of a name winning.
///
/// - A header is a line that starts with `[`, named up to its first `]`; one with no `]` is skipped.
/// - A line starting with `;` or `//` is a comment. A line with no `=` that is no header is ignored.
/// - A line splits at its first `=`: the key is trimmed, the value kept as written after the `=`
///   (`Section.writtenLines`). `Section.lines` and `subscript(section:key:)` trim only its end, so a
///   value that starts with spaces keeps them; `value(_:_:)` trims both ends.
/// - Lines before the first header belong to a section named "".
/// - Sections, and each section's lines, keep file order, duplicates included.
/// - A header repeated later either carries on the first section of its name, or is ignored with its
///   lines (`RepeatedSections`).
struct INIFile: Sendable {
    /// What a second `[Section]` header of a name means. Win32's `GetPrivateProfileString` reads the
    /// first section of a name and nothing after; Delphi's `TMemIniFile` adds the later one's lines to it.
    enum RepeatedSections: Sendable {
        case ignored
        case continued
    }

    struct Section: Sendable {
        /// As the file first spells it.
        let name: String
        /// Every `key=value` line, in file order, duplicates included; each value without the spaces
        /// it ends with.
        fileprivate(set) var lines: [(key: String, value: String)] = []
        /// The same lines with each value as written, the spaces it ends with kept.
        fileprivate(set) var writtenLines: [(key: String, value: String)] = []
        /// Lowercased key to its first value.
        private var first: [String: String] = [:]

        fileprivate init(name: String) { self.name = name }

        fileprivate mutating func append(_ key: String, written: Substring) {
            let value = String(written.reversed().drop { $0.isWhitespace && !$0.isNewline }.reversed())
            lines.append((key, value))
            writtenLines.append((key, String(written)))
            let lower = key.lowercased()
            if first[lower] == nil { first[lower] = value }
        }

        /// The first value of `key`, without the spaces it ends with.
        subscript(key: String) -> String? { first[key.lowercased()] }
    }

    /// In file order.
    private(set) var sections: [Section] = []
    private var index: [String: Int] = [:]

    init(_ text: String, repeatedSections: RepeatedSections) {
        var current: Int? = nil
        var started = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                guard let close = line.firstIndex(of: "]") else { continue }
                let name = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                let repeated = index[name.lowercased()] != nil
                current = repeated && repeatedSections == .ignored ? nil : section(named: name)
                started = true
                continue
            }
            guard !line.hasPrefix(";"), !line.hasPrefix("//"), let equals = raw.firstIndex(of: "=") else { continue }
            if !started {
                current = section(named: "")
                started = true
            }
            guard let at = current else { continue }
            sections[at].append(raw[..<equals].trimmingCharacters(in: .whitespaces), written: raw[raw.index(after: equals)...])
        }
    }

    subscript(section: String) -> Section? { index[section.lowercased()].map { sections[$0] } }

    /// `section`'s `key` without the spaces its value ends with; nil when either is missing.
    subscript(section: String, key: String) -> String? { self[section]?[key] }

    /// `section`'s `key` with both ends trimmed, as `GetPrivateProfileString` returns it.
    func value(_ section: String, _ key: String) -> String? {
        self[section, key]?.trimmingCharacters(in: .whitespaces)
    }

    private mutating func section(named name: String) -> Int {
        let lower = name.lowercased()
        if let at = index[lower] { return at }
        sections.append(Section(name: name))
        index[lower] = sections.count - 1
        return sections.count - 1
    }
}
