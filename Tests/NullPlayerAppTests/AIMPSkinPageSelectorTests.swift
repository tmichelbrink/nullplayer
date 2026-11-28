import XCTest
@testable import NullPlayer

/// `PageSelector`, as AIMP 5.40 draws and clicks one (a Tunes test skin with M5's dots in place of
/// its artist line, in AIMP under Wine): a cell a frame wide for each page of the group its
/// `Action` names, from the control's top left, the shown page's lit; a click on a cell shows it.
final class AIMPSkinPageSelectorTests: XCTestCase {
    /// A `width`×`height` `ACLIMG32` picture of `frames` frames stacked: its header, a raw `bits`
    /// chunk, and a `layt` chunk with the frame count.
    private static func picture(_ width: Int, _ height: Int, frames: Int) -> Data {
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let pixels = Data(repeating: 0xFF, count: width * height * 4)
        var data = Data("ACLIMG32".utf8) + Data(count: 8)
        data += Data("bits".utf8) + u32(12 + pixels.count)
        data += u32(0) + u32(width) + u32(height) + pixels
        data += Data("layt".utf8) + u32(5) + Data([1]) + u32(frames)
        return data
    }

    @MainActor func testACellForEachPageTheShownOneLitAndEachClickable() throws {
        let page = { (name: String) in #"<item class="LayoutContainer" name="\#(name)"/>"# }
        let skin = try AIMPSkinScriptTests.skin(form: """
        <layout><items><item class="LayoutContainer" name="Main">
          <properties><property name="SizeMinimal" value="200,100"/></properties>
          <items><item class="LayoutTabbedGroup" name="Info"><properties><property name="Alignment" value="laClient"/></properties>
            <items>\(page("First"))\(page("Second"))\(page("Third"))</items></item></items>
          <controls><control class="PageSelector" name="Dots"><properties><property name="Bindings">
            <link Source="Info" SourcePin="Pages" TargetPin="Action"/></property>
            <property name="Skin" value="Dots"/><property name="PlaceInfo" margins="10,20,0,0" Size="100,20"/></properties></control></controls>
        </item></items></layout>
        """, files: [("Dots.img", Self.picture(19, 26, frames: 2))])
        guard case .control(let control)? = skin.index.byName["Dots"] else { return XCTFail("no selector") }
        guard case .pageSelector(let group) = control.kind else { return XCTFail("not a page selector") }
        XCTAssertEqual(group, "Info")

        var state = AIMPSkinState()
        state.script["Info"].activePage = 1
        let frame = try XCTUnwrap(AIMPSkinRenderer.frame(skin, size: CGSize(width: 200, height: 100), form: nil,
                                                         host: AIMPSkinHostState(), state: state))
        let dots = frame.targets.filter { $0.name == "Dots" }
        let origin = try XCTUnwrap(frame.namedRects["Dots"]).origin
        XCTAssertEqual(dots.map(\.rect), (0..<3).map { CGRect(x: origin.x + CGFloat($0) * 19, y: origin.y, width: 19, height: 13) })
        XCTAssertEqual(dots.map(\.kind), (0..<3).map { .page(group: "Info", step: AIMPSkinStep(String($0))) })
    }
}
