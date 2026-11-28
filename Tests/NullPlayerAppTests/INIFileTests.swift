import XCTest
@testable import NullPlayer

final class INIFileTests: XCTestCase {
    private let text = "key=before\n[FILE]\n SkinName =Micro Aimp \n; note=x\n// also=x\nSkinName=second\n[Label] trailing\nTemplate= / %S\n[file]\nAuthor=Me\n[broken\nlost=1\n"

    func testSectionsAndKeysInAnyCaseTheValueAsWritten() {
        let ini = INIFile(text, repeatedSections: .continued)
        XCTAssertEqual(ini["file", "skinname"], "Micro Aimp", "the value's end trimmed")
        XCTAssertEqual(ini["LABEL", "Template"], " / %S", "the spaces a value starts with are kept")
        XCTAssertEqual(ini.value("label", "template"), "/ %S", "value(_:_:) trims both ends")
        XCTAssertEqual(ini["", "key"], "before", "lines before the first header")
        XCTAssertEqual(ini.sections.map(\.name), ["", "FILE", "Label"])
        XCTAssertEqual(ini["FILE"]?.writtenLines.first?.value, "Micro Aimp ")
    }

    func testCommentsAndUnclosedHeadersAreSkipped() {
        let ini = INIFile(text, repeatedSections: .continued)
        XCTAssertNil(ini["file", "; note"])
        XCTAssertNil(ini["file", "// also"])
        XCTAssertEqual(ini["file", "lost"], "1", "a header with no ] is skipped: its lines stay in the section before")
    }

    /// As `GetPrivateProfileString` reads it, the first value of a key wins; every line stays, in order.
    func testTheFirstValueOfAKeyWins() {
        let ini = INIFile(text)
        XCTAssertEqual(ini.value("FILE", "SkinName"), "Micro Aimp")
        XCTAssertEqual(ini["FILE"]?.lines.map(\.value), ["Micro Aimp", "second"])
    }

    /// A repeated header is ignored unless asked otherwise, as Sonique's `skin.ini` is read.
    func testARepeatedHeaderIsIgnoredByDefault() {
        XCTAssertNil(INIFile(text).value("FILE", "Author"))
    }

    func testARepeatedHeaderCarriesOnOrIsIgnored() {
        XCTAssertEqual(INIFile(text, repeatedSections: .continued)["FILE", "Author"], "Me")
        XCTAssertNil(INIFile(text, repeatedSections: .ignored)["FILE", "Author"])
        XCTAssertEqual(INIFile(text, repeatedSections: .ignored)["FILE", "SkinName"], "Micro Aimp")
    }
}
