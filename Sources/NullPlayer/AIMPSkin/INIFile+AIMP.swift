import Foundation

extension INIFile {
    /// An INI file as AIMP writes them: `main.ini` (AIMP 3.0 and AIMP 2 skins) and `.lng` language
    /// files, UTF-16 (a byte-order mark, or little-endian without one). Read once per file, as Delphi's
    /// `TMemIniFile` reads it: names in any case (AIMP 2's version-2 `main.ini` spells `PLAYBTN`,
    /// `Volumebar`), a header repeated later carrying on its section, and sections and their lines in
    /// file order, as AIMP 2's objects stack in section order.
    init(aimpUTF16 data: Data, name: String) throws {
        guard let text = String(data: data, encoding: .utf16) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is not UTF-16 text.")
        }
        self.init(text, repeatedSections: .continued)
    }
}
