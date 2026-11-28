import CoreGraphics
import XCTest
@testable import NullPlayer

/// `AIMPSkinStore`: what AIMP mode keeps of each installed skin, by its installed name, so two skins
/// that embed one name (or none) never share a record.
final class AIMPSkinStoreTests: XCTestCase {
    /// Hidden and never recorded are different answers: only the first overrides a skin's default.
    func testVisibilityTellsClosedFromNeverRecorded() {
        let store = AIMPSkinStore(defaults: scopedDefaults())
        let a = store.skin("A"), b = store.skin("B")
        XCTAssertEqual(a.visibility, [:])
        a.setVisibility(false, window: "Speakers")
        a.setVisibility(true, window: "Amp")
        b.setVisibility(true, window: "Speakers")
        XCTAssertEqual(a.visibility, ["speakers": false, "amp": true])
        XCTAssertEqual(b.visibility, ["speakers": true])
        XCTAssertNil(a.visibility["remote"])
    }

    /// A size is kept per skin and form, the main form apart from the others; an empty one is none.
    func testSizesArePerSkinAndForm() {
        let store = AIMPSkinStore(defaults: scopedDefaults())
        let a = store.skin("A")
        XCTAssertNil(a.size(form: nil))
        a.setSize(CGSize(width: 400, height: 300), form: nil)
        a.setSize(CGSize(width: 200, height: 100), form: "Playlist")
        store.skin("B").setSize(CGSize(width: 0, height: 100), form: nil)
        XCTAssertEqual(a.size(form: nil), CGSize(width: 400, height: 300))
        XCTAssertEqual(a.size(form: "playlist"), CGSize(width: 200, height: 100))
        XCTAssertNil(store.skin("B").size(form: nil), "an empty size is none")
        XCTAssertNil(store.skin("").size(form: nil), "a skin's records are its installed name's alone")
    }

    func testTheVisualizationModeIsKeptPerSkin() {
        let store = AIMPSkinStore(defaults: scopedDefaults())
        XCTAssertNil(store.skin("A").visualMode)
        store.skin("A").setVisualMode(.vu)
        XCTAssertEqual(store.skin("A").visualMode, .vu)
        XCTAssertNil(store.skin("B").visualMode)
    }

    /// The origins go where `.wmz`-style origins of the family always went.
    func testOriginsAreTheFamilysWindowStore() {
        let defaults = scopedDefaults()
        AIMPSkinStore(defaults: defaults).skin("Deck").setOrigin(CGPoint(x: 1, y: 2), window: "Speaker")
        XCTAssertEqual(SkinWindowStore(defaults: defaults, keys: .aimp).origin(skin: "Deck", window: "Speaker"), CGPoint(x: 1, y: 2))
        XCTAssertEqual(defaults.dictionary(forKey: "aimpViewOrigins") as? [String: [Double]], ["4:deck|speaker": [1, 2]])
    }
}
