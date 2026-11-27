import XCTest
@testable import NullPlayer

/// A display bound to the playing file's `FileInfo`: its template's text, read as a number when the
/// link has an `Expression` (AIMP 5.40 shows Sony Media Tower's `%IN` through `Value MOD 10000` as 1,
/// where `%IN` alone reads "01").
final class AIMPSkinFileInfoTextTests: XCTestCase {
    private func text(expression: String?) throws -> String {
        let shaped = expression.map { #" Expression="\#($0)""# } ?? ""
        let main = """
        <layout><items><item name="Body"><properties><property name="Size" value="120,60"/>
          <property name="Color" value="-1"/></properties><controls>
          <control class="TextDisplay" name="Count"><properties><property name="Bindings">
            <link Source="prvPlayingFileInfo" SourcePin="FileInfo" TargetPin="DisplayValue"\(shaped) TextFormat="%IN"/>
          </property><property name="PlaceInfo" margins="0,0,0,0" Size="40,20"/></properties></control>
        </controls></item></items></layout>
        """
        let skin = try AIMPSkinLoader.load(data: AIMPSkinFormWindowMaterializerTests.project([("AIMPMainForm.xml", main)]))
        guard case .control(let control)? = skin.index.byName["Count"] else { XCTFail("no control"); return "" }
        var host = AIMPSkinHostState()
        host.player.playlistIndex = 0
        return AIMPSkinDataflow(skin: skin, host: host, state: AIMPSkinState()).displayText(control)
    }

    func testAnExpressionReadsTheTextAsANumber() throws {
        XCTAssertEqual(try text(expression: nil), "01")
        XCTAssertEqual(try text(expression: "Value MOD 10000"), "1")
    }
}
