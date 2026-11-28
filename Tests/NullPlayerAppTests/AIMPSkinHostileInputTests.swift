import XCTest
@testable import NullPlayer

/// One crafted skin per loading limit (`AIMPSkinPolicy`, `AM0002`–`AM0009`): each is refused with its
/// code, cheaply, before the work the limit guards against. The script, layout and dataflow limits
/// have their own (`AIMPSkinScriptTests`, `AIMPSkinModelTests`: the step, depth, text and expression
/// limits; a dock site naming its own form; a concatenator ladder).
final class AIMPSkinHostileInputTests: XCTestCase {
    private static func u32(_ value: Int) -> Data { AIMPTestProject.u32(value) }

    /// A project file (`ACSJ`) of `entries`, its count `count` when given.
    private static func project(_ entries: [(String, Data)], count: Int? = nil) -> Data {
        AIMPTestProject.data(entries, count: count)
    }

    private static let form = ("AIMPMainForm.xml", Data(#"<form name="AIMPMainForm"/>"#.utf8))

    /// An `ACLIMG32` header and a `bitz` chunk claiming `width`×`height`, with `frames` stacked;
    /// no pixels: the header alone is what loading reads.
    private static func acl(width: Int, height: Int, frames: Int = 1) -> Data {
        var data = Data("ACLIMG32".utf8) + Data(count: 8)
        data += Data("bitz".utf8) + u32(16) + u32(0) + u32(width) + u32(height) + u32(0)
        if frames > 1 { data += Data("layt".utf8) + u32(5) + Data([1]) + u32(frames) }
        return data
    }

    private func refused(_ data: Data, _ code: AIMPSkinDiagnosticCode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AIMPSkinLoader.load(data: data), file: file, line: line) { error in
            XCTAssertEqual((error as? AIMPSkinFinding)?.code, code, "\(error)", file: file, line: line)
        }
    }

    /// AM0002: a file past `fileBytes` is refused from its size, never read (a sparse file here).
    func testAFileTooLargeIsRefusedUnread() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hostile-\(UUID().uuidString).acs5")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(AIMPSkinPolicy.fileBytes) + 1)
        try handle.close()
        XCTAssertThrowsError(try AIMPSkinLoader.load(contentsOf: url)) { error in
            XCTAssertEqual((error as? AIMPSkinFinding)?.code, .fileTooLarge)
        }
    }

    /// AM0003: a count past `entries` is refused before an entry is read.
    func testTooManyEntriesAreRefused() {
        refused(Self.project([Self.form], count: AIMPSkinPolicy.entries + 1), .tooManyEntries)
    }

    /// AM0004: an entry whose size runs past the file.
    func testAnEntryPastTheEndIsRefused() {
        var data = Self.project([])
        data.replaceSubrange((data.count - 4)..<data.count, with: Self.u32(1))
        data += AIMPTestProject.utf16LE("AIMPMainForm.xml") + Self.u32(1 << 20) + Data("<form/>".utf8)
        refused(data, .entryOutOfBounds)
    }

    /// AM0005: an `.acs4` declaring an inflated body past `inflatedBytes` is refused from the
    /// declaration, before a byte is inflated.
    func testAnInflatedSizePastTheLimitIsRefused() {
        var file = Array("ACS4".utf8) + [0x00] + Array(Self.u32(450))
        let key: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        // The marker at 9, scrambled with the key: byte i XORed with key[i mod 4].
        file += Array("3SCA".utf8).enumerated().map { $0.element ^ key[(9 + $0.offset) % 4] }
        let meta = Array(AIMPTestProject.utf16LE("Test") + AIMPTestProject.utf16LE("") + AIMPTestProject.utf16LE("") + [0])
        file += Array(Self.u32(meta.count))
        file += meta.enumerated().map { $0.element ^ key[(17 + $0.offset) % 4] }
        file += Array(Self.u32(AIMPSkinPolicy.inflatedBytes + 1)) + [0x78, 0x9C, 0x03, 0x00]
        refused(Data(file), .inflatedTooLarge)
    }

    /// AM0006: a picture whose frames are wider than `imageSide`.
    func testAnImageTooWideIsRefused() {
        refused(Self.project([Self.form, ("Wide.img", Self.acl(width: AIMPSkinPolicy.imageSide + 1, height: 1))]), .imageTooLarge)
    }

    /// AM0007: a picture whose frames each fit, but whose pixels together pass the budget.
    func testAnImagePastThePixelBudgetIsRefused() {
        let side = AIMPSkinPolicy.imageSide
        refused(Self.project([Self.form, ("Tall.img", Self.acl(width: side, height: side * 2, frames: 2))]), .pixelBudgetExceeded)
    }

    /// AM0009: a form nested deeper than `xmlDepth` does not parse.
    func testAFormNestedTooDeepIsRefused() {
        let depth = AIMPSkinPolicy.xmlDepth + 1
        let xml = String(repeating: "<item>", count: depth) + String(repeating: "</item>", count: depth)
        let form = #"<form name="AIMPMainForm">"# + xml + "</form>"
        XCTAssertThrowsError(try AIMPSkinLoader.load(data: Self.project([("AIMPMainForm.xml", Data(form.utf8))]))) { error in
            XCTAssertTrue("\(error)".contains("deeper"), "\(error)")
        }
    }

    /// AM0005: the scripts are charged against the load's inflation budget with the pictures, before
    /// each is inflated: a skin whose pictures leave too little for its scripts does not load.
    func testScriptsShareTheLoadsInflationBudget() throws {
        let archive = try AIMPSkinArchive.read(Self.project([Self.form, ("Big.fsxml", Data(count: 64))]))
        var findings: [AIMPSkinFinding] = []
        var inflated = AIMPSkinPolicy.loadInflatedBytes - 63
        XCTAssertThrowsError(try AIMPSkinScript.Library(archive, inflated: &inflated, findings: &findings)) { error in
            XCTAssertEqual((error as? AIMPSkinFinding)?.code, .inflatedTooLarge)
        }
        inflated = AIMPSkinPolicy.loadInflatedBytes - 64
        XCTAssertNoThrow(try AIMPSkinScript.Library(archive, inflated: &inflated, findings: &findings), "exactly the limit")
    }

    /// AM0009: an `SXML` name table counting more names than the node limit is refused from its
    /// count, before a name is read.
    func testAnSXMLNameTablePastTheLimitIsRefused() {
        var count = AIMPSkinPolicy.xmlNodes + 1, varint: [UInt8] = []
        while count >= 0x80 { varint.append(UInt8(count & 0x7F) | 0x80); count >>= 7 }
        varint.append(UInt8(count))
        let data = Data("SXML".utf8) + Self.u32(1) + Self.u32(0) + Data([1] + varint)
        XCTAssertThrowsError(try AIMPNode.parse(data, name: "Names.xml")) { error in
            XCTAssertEqual((error as? AIMPSkinFinding)?.code, .xmlMalformed)
            XCTAssertTrue("\(error)".contains("names"), "\(error)")
        }
    }

    /// An AIMP 3.0 object's size near `Int.max` is held as the layout's numbers are, rather than
    /// trapping where it is made whole again.
    func testAnAIMP3ObjectsHugeSizeIsHeld() throws {
        let ini = INIFile("[Parents]\nVolumeBar=MAIN\n[VolumeBar]\nPlaceWidth=9223372036854775807\nPlaceHeight=-9223372036854775807\n",
                          repeatedSections: .continued)
        let object = try XCTUnwrap(AIMPSkinAIMP3.objects(ini).first)
        XCTAssertEqual(object.size, CGSize(width: 1_000_000, height: -1_000_000))
        XCTAssertEqual(AIMPSkinAIMP3.Shape.place(anchors: object.anchors, margins: object.margins, size: object.size).size?.width, 1_000_000)
    }

    /// Only the DPI suffixes mark a picture's variants: `Meter-2` is a picture of its own.
    func testOnlyDPISuffixesAreVariants() throws {
        let skin = try AIMPSkinLoader.load(data: Self.project([
            Self.form, ("Meter-2.img", Self.acl(width: 4, height: 4)), ("Meter-120.img", Self.acl(width: 5, height: 5)),
        ]))
        XCTAssertNotNil(skin.images["meter-2.img"])
        XCTAssertNil(skin.images["meter-120.img"], "a DPI variant is left out")
    }

    /// An `ACLIMG32`'s size is read from the chunk its pixels are: a `bitz` too short for its packed
    /// size is passed over for both, so its 2×2 cannot lay out `bits`' 1×4.
    func testAnACLImagesSizeAndPixelsComeFromOneChunk() throws {
        var data = Data("ACLIMG32".utf8) + Data(count: 8)
        data += Data("bitz".utf8) + Self.u32(12) + Self.u32(0) + Self.u32(2) + Self.u32(2)
        data += Data("bits".utf8) + Self.u32(28) + Self.u32(0) + Self.u32(1) + Self.u32(4) + Data(repeating: 0xFF, count: 16)
        let image = try AIMPSkinImage(data, name: "Mixed.img", budget: AIMPSkinPixelBudget(), source: { data })
        XCTAssertEqual([image.width, image.height], [1, 4])
        XCTAssertNotNil(image.frame(0), "its pixels decode at that size")
    }

    /// An entry name met twice keeps its first entry: a later copy cannot swap the form or a
    /// picture behind the one read first.
    func testADuplicateEntryKeepsTheFirst() throws {
        let data = Self.project([Self.form, ("aimpmainform.xml", Data("<form".utf8))])
        let archive = try AIMPSkinArchive.read(data)
        XCTAssertEqual(try archive.entry("AIMPMainForm.xml").map(archive.payload), Self.form.1)
        XCTAssertNoThrow(try AIMPSkinLoader.load(data: data))
    }
}
