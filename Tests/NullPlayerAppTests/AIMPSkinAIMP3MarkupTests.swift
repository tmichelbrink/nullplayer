import XCTest
@testable import NullPlayer

/// How AIMP 3 skins write some markup, which AIMP 5.40 reads as it does its own (AyonPlayer Black,
/// Black Glass, ICS, Paline, Anime Gold VI).
final class AIMPSkinAIMP3MarkupTests: XCTestCase {
    /// `PlaceInfo`'s `size` in lower case still sizes the control.
    func testAttributeNamesMatchWhateverTheirCase() {
        let place = AIMPNode.element("property", ["name": "PlaceInfo", "anchors": "1,1,0,0", "margins": "252,71,66,96", "size": "31,31"])
        XCTAssertEqual(place["Size"], "31,31")
        XCTAssertEqual(AIMPPlacement.Info(place).size, CGSize(width: 31, height: 31))
        let both = AIMPNode.element("property", ["Size": "10,10", "size": "31,31"])
        XCTAssertEqual(both["Size"], "10,10", "an exact match wins")
    }

    /// A link that names only an action binds the control's Action and State to it.
    func testALinkNamingOnlyAnActionBindsItsActionAndState() {
        let button = AIMPNode.element("control", ["class": "Button", "name": "PlayPauseBtn"], [
            AIMPNode.propertyList([AIMPNode.bindings(AIMPNode.element("link", ["Source": "acPlayerPlayPause"]))]),
        ])
        let bindings = AIMPSkinBindings(button, names: .init())
        XCTAssertEqual(bindings["Action"]?.source, "acPlayerPlayPause")
        XCTAssertEqual(bindings["Action"]?.pin, "Action")
        XCTAssertEqual(bindings["State"]?.pin, "State")

        let provider = AIMPNode.element("control", ["class": "Button"], [
            AIMPNode.propertyList([AIMPNode.bindings(AIMPNode.element("link", ["Source": "MyCounter"]))]),
        ])
        XCTAssertNil(AIMPSkinBindings(provider, names: .init())["Action"], "only actions are expanded")
    }
}
