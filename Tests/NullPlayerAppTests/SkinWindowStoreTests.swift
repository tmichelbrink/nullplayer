import CoreGraphics
import XCTest
@testable import NullPlayer

/// `SkinWindowStore`, the per-skin window origins, open windows and visibility a skin family keeps.
/// `.wmz` must find its geometry under exactly the defaults keys and values it always wrote, or every
/// user's arranged panels reset on upgrade.
final class SkinWindowStoreTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "SkinWindowStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testWMPKeepsItsDefaultsKeysAndValues() {
        let frames = WMPViewFrameStore(defaults: defaults)
        frames.windows.setOrigin(CGPoint(x: 12, y: 340), skin: "Skin A", window: "plView")
        frames.windows.setOpenWindows(["plView", "eqView"], skin: "Skin A")
        frames.setSize(.init(width: 320, height: 180), skin: "Skin A", view: "plView")

        XCTAssertEqual(defaults.dictionary(forKey: "wmpViewOrigins") as? [String: [Double]],
                       ["6:skin a|plview": [12, 340]])
        XCTAssertEqual(defaults.dictionary(forKey: "wmpOpenViews") as? [String: [String]],
                       ["6:skin a": ["plView", "eqView"]])
        XCTAssertEqual(defaults.dictionary(forKey: "wmpViewSizes") as? [String: [Double]],
                       ["6:skin a|plview": [320, 180]])
        XCTAssertNil(defaults.object(forKey: "wmpWindowVisibility"), "WMP records no visibility")
        XCTAssertEqual(SkinWindowStore.skinKey("Skin A"), "6:skin a")

        // Values written by an older build read back unchanged.
        defaults.set(["5:other|full": [1.5, 2.5]], forKey: "wmpViewOrigins")
        XCTAssertEqual(frames.windows.origin(skin: "OTHER", window: "Full"), CGPoint(x: 1.5, y: 2.5))
        XCTAssertNil(frames.windows.origin(skin: "Skin A", window: "plView"))

        frames.windows.setOpenWindows([], skin: "Skin A")
        XCTAssertEqual(defaults.dictionary(forKey: "wmpOpenViews")?.isEmpty, true,
                       "an empty list removes the skin's entry")
    }

    func testOriginsAndOpenWindowsArePerSkinAndRefuseNonFiniteValues() {
        let store = SkinWindowStore(defaults: defaults, family: "test")
        store.setOrigin(CGPoint(x: 1, y: 2), skin: "A", window: "w")
        store.setOrigin(CGPoint(x: CGFloat.nan, y: 2), skin: "B", window: "w")
        XCTAssertEqual(store.origin(skin: "a", window: "W"), CGPoint(x: 1, y: 2))
        XCTAssertNil(store.origin(skin: "B", window: "w"))
        store.setOpenWindows(["w"], skin: "A")
        XCTAssertEqual(store.openWindows(skin: "A"), ["w"])
        XCTAssertEqual(store.openWindows(skin: "B"), [])
        XCTAssertEqual(Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("test") }),
                       ["testViewOrigins", "testOpenViews"])
    }

    /// Hidden and never recorded are different answers: only the first overrides a skin's default.
    func testVisibilityTellsClosedFromNeverRecorded() {
        let store = SkinWindowStore(defaults: defaults, family: "test")
        XCTAssertEqual(store.visibility(skin: "A"), [:])
        store.setVisibility(false, window: "Speakers", skin: "A")
        store.setVisibility(true, window: "Amp", skin: "A")
        store.setVisibility(true, window: "Speakers", skin: "B")
        XCTAssertEqual(store.visibility(skin: "A"), ["speakers": false, "amp": true])
        XCTAssertEqual(store.visibility(skin: "B"), ["speakers": true])
        XCTAssertNil(store.visibility(skin: "A")["remote"])
    }
}
