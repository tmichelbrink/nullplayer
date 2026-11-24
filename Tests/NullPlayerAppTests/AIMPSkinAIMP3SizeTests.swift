import XCTest
@testable import NullPlayer

/// How an AIMP 3.0 skin's layout sizes its window, as AIMP 5.40 opens it: the items' own limits
/// count, the playlist frame's floating caption does not, and the list gets no room of its own.
final class AIMPSkinAIMP3SizeTests: XCTestCase {
    /// `MinSize`, `MaxSize` and the resize flags read as the AIMP 4 properties AIMP's conversion writes.
    func testAnItemsLimitsReadAsAIMP4Properties() {
        let source = AIMPNode.element("item", ["Class": "TAIMPLayoutContainerItem", "Name": "Container1", "MinSize": "176,301",
                                               "MaxSize": "741,0", "AllowResizeByHeight": "0", "AutoSize": "1"])
        let limits = Dictionary(uniqueKeysWithValues: AIMPSkinLegacy.Translator.limits(source).compactMap { node in
            node["name"].map { ($0, node["value"] ?? "") }
        })
        XCTAssertEqual(limits, ["SizeMinimal": "176,301", "SizeMaximal": "741,0", "AllowResizeByHeight": "False", "AutoSize": "True"])
        XCTAssertTrue(AIMPSkinLegacy.Translator.limits(AIMPNode.element("item", ["Name": "Bar"])).isEmpty)
    }

    /// Experience's cover panel says `MinSize="176,301"`: AIMP 5.40 opens the skin 579 tall.
    func testExperienceOpensWithRoomForItsCoverPanel() throws {
        let skin = try AIMPCorpusSkin.load("185-Experience_v1.82.acs3")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 741, height: 579))
    }

    /// NGuvu's playlist caption (`PlsTopDock`) shows only while the frame floats; its bars' 295-px
    /// `MinSize` under the 230-px deck: AIMP 5.40 opens 568 tall.
    func testNGuvuOpensWithoutItsFloatingCaption() throws {
        let skin = try AIMPCorpusSkin.load("352-NGuvu_v2.2_Vert.Tabs_Layout.acs3")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 454, height: 568))
    }

    /// Bloom's list takes no room: AIMP 5.40 opens its deck, tab row, playlist bar and transport, 282 tall.
    func testBloomOpensWithNoListRoom() throws {
        let skin = try AIMPCorpusSkin.load("401-Bloom.acs3")
        XCTAssertEqual(AIMPSkinRenderer.naturalSize(skin), CGSize(width: 500, height: 282))
    }
}
