import XCTest
@testable import NullPlayer

/// A fixed window grows to hold an item that starts hidden once it is shown (Cassette-3D's VU meter
/// panel over its bottom-docked cassette), as AIMP fits such a window to what it holds.
final class AIMPSkinShownItemFitTests: XCTestCase {
    /// The same fit on a small skin of its own, needing no installed corpus: a 60-px panel that
    /// starts hidden over a 100-px bottom-docked item, overlapping it by 10 px.
    @MainActor func testAShownPanelGrowsTheWindowAndKeepsTheBottomItem() throws {
        let skin = try AIMPSkinScriptTests.skin(form: """
        <layout><items><item class="LayoutContainer" name="Main">
          <properties><property name="SizeMinimal" value="200,0"/><property name="Texture" value="Main"/></properties>
          <items>
            <item class="LayoutContainer" name="Meters"><properties><property name="AlignmentMargins" value="0,0,0,-10"/>
              <property name="Texture" value="Meters"/><property name="InitialVisible" value="False"/></properties></item>
            <item class="LayoutContainer" name="Cassette"><properties><property name="SizeMaximal" value="200,100"/>
              <property name="SizeMinimal" value="200,100"/><property name="Alignment" value="laBottom"/>
              <property name="Texture" value="Cassette"/></properties></item>
          </items>
        </item></items></layout>
        """, files: [("Main.img", Self.picture(200, 100)), ("Meters.img", Self.picture(200, 60)),
                     ("Cassette.img", Self.picture(200, 100))])
        let natural = CGSize(width: 200, height: 100)
        XCTAssertEqual(AIMPSkinRenderer.fittedSize(skin, natural: natural, state: AIMPSkinState()), natural,
                       "a hidden panel takes no room")

        var state = AIMPSkinState()
        state.script["Meters"].visible = true
        let fitted = AIMPSkinRenderer.fittedSize(skin, natural: natural, state: state)
        XCTAssertEqual(fitted, CGSize(width: 200, height: 150), "60-px panel less its 10-px overlap over the 100-px item")

        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: state)
        let tree = try XCTUnwrap(AIMPSkinLayout(flow: flow).tree(size: fitted))
        let cassette = try XCTUnwrap(tree.offers.namedRects["Cassette"])
        let meters = try XCTUnwrap(tree.offers.namedRects["Meters"])
        XCTAssertEqual(cassette.height, 100, "the bottom item is not shrunk")
        XCTAssertEqual(cassette.maxY, fitted.height)
        XCTAssertEqual(meters.maxY - 10, cassette.minY, "the panel overlaps it by its -10 margin")
    }

    /// A solid `width`×`height` `ACLIMG32` picture: its 16-byte header, then a raw `bits` chunk.
    private static func picture(_ width: Int, _ height: Int) -> Data {
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let pixels = Data(repeating: 0xFF, count: width * height * 4)
        return Data("ACLIMG32".utf8) + Data(count: 8) + Data("bits".utf8) + u32(12 + pixels.count)
            + u32(0) + u32(width) + u32(height) + pixels
    }

    func testCassette3DGrowsForItsVUMeters() throws {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NullPlayer/AIMPSkins/Cassette-3D.acs4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "Cassette-3D is not installed")
        let skin = try AIMPSkinLoader.load(contentsOf: file)
        let natural = try XCTUnwrap(skin.naturalSize(form: nil))
        XCTAssertEqual(AIMPSkinRenderer.fittedSize(skin, natural: natural, state: AIMPSkinState()), natural,
                       "hidden meters take no room")

        var state = AIMPSkinState()
        state.script["VU_Container"].visible = true
        let fitted = AIMPSkinRenderer.fittedSize(skin, natural: natural, state: state)
        XCTAssertEqual(fitted.width, natural.width)
        XCTAssertEqual(fitted.height, 610, "206-px meters less their 36-px overlap over the 440-px cassette")

        // Laid out at the fitted size, the cassette keeps its whole 440 px below the meters' slot.
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: state)
        let tree = try XCTUnwrap(AIMPSkinLayout(flow: flow).tree(size: fitted))
        let cassette = try XCTUnwrap(tree.offers.namedRects["Cassette_Container"])
        let meters = try XCTUnwrap(tree.offers.namedRects["VU_Container"])
        XCTAssertEqual(cassette.height, 440)
        XCTAssertEqual(cassette.maxY, fitted.height)
        XCTAssertEqual(meters.minY, 0)
        XCTAssertEqual(meters.maxY - 36, cassette.minY, "the meters overlap the cassette by their -36 margin")
    }
}
