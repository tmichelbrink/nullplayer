import XCTest
@testable import NullPlayer

/// A skin's form windows (`AIMPSkinFormWindowMaterializer`): made only once a form is wanted, never
/// for a docked one, placed once (the user's place over the skin's, always reachable), torn down
/// without the deck, and their shown or hidden kept per skin. Skins are synthesized.
@MainActor
final class AIMPSkinFormWindowMaterializerTests: XCTestCase {
    private var deck: SkinnedBorderlessWindow!
    private var deckView: AIMPSkinMainView!

    override func setUp() async throws {
        deck = SkinnedBorderlessWindow(contentRect: NSRect(x: 800, y: 400, width: 100, height: 40),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        deck.isReleasedWhenClosed = false
        deckView = AIMPSkinMainView()
        deck.contentView = deckView
        deck.orderFront(nil)
    }

    override func tearDown() async throws {
        deck.orderOut(nil)
        deck = nil
        deckView = nil
    }

    func testAFormGetsAWindowOnlyOnceItIsWanted() throws {
        let (materializer, runtime) = try make(store())
        defer { materializer.teardown() }
        try waitForContent(materializer, runtime)
        materializer.update(runtime.flow, deck: deck)
        XCTAssertTrue(materializer.materializedAuxiliaryWindows.isEmpty, "InitialVisible False: no window yet")
        XCTAssertEqual(materializer.menuItems(runtime.flow) { _, _ in }.map(\.title), ["Speaker"], "listed without a window")

        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        let window = try XCTUnwrap(materializer.window(for: "Speaker"))
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.accessibilityIdentifier(), "AIMPSkinForm_Speaker")
        XCTAssertTrue(window.delegate === materializer)

        runtime.state.script["Speaker"].visible = false
        materializer.update(runtime.flow, deck: deck)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(materializer.materializedAuxiliaryWindows.count, 1, "kept for the next show")
    }

    func testADockedFormNeverGetsAWindow() throws {
        let (materializer, runtime) = try make(store(), docked: true)
        defer { materializer.teardown() }
        try waitForContent(materializer, runtime)
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        XCTAssertNil(materializer.window(for: "Speaker"), "its site shows it")
    }

    func testTheSkinsPlacementThenTheUsersWinsAndAWindowIsAlwaysReachable() throws {
        let store = store()
        var (materializer, runtime) = try make(store)
        try waitForContent(materializer, runtime)
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        var window = try XCTUnwrap(materializer.window(for: "Speaker"))
        XCTAssertEqual(window.frame.maxX, deck.frame.minX, "the skin's side: left of the deck")
        XCTAssertEqual(window.frame.maxY, deck.frame.maxY, "tops level")
        materializer.teardown()

        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let left = CGPoint(x: screen.minX + 40, y: screen.maxY - 60)
        store.setOrigin(left, window: "Speaker")
        (materializer, runtime) = try make(store)
        try waitForContent(materializer, runtime)
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        window = try XCTUnwrap(materializer.window(for: "Speaker"))
        XCTAssertEqual(NSPoint(x: window.frame.minX, y: window.frame.maxY), left, "where the user left it")
        materializer.teardown()

        store.setOrigin(CGPoint(x: -100_000, y: -100_000), window: "Speaker")
        (materializer, runtime) = try make(store)
        defer { materializer.teardown() }
        try waitForContent(materializer, runtime)
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        window = try XCTUnwrap(materializer.window(for: "Speaker"))
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }, "rescued onto a screen")
    }

    /// Two forms the skin opens below a deck at the foot of the screen (Tascam Fireone's playlist and
    /// library): each wholly on the screen, neither over the other nor over the deck.
    func testFormsOpenedBelowTheDeckStayOnScreenAndApart() throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        deck.setFrameOrigin(NSPoint(x: screen.midX - 50, y: screen.minY + 10))
        let (materializer, runtime) = try make(store(), below: ["Playlist", "Library"])
        defer { materializer.teardown() }
        try waitForContent(materializer, runtime)
        runtime.state.script["Playlist"].visible = true
        runtime.state.script["Library"].visible = true
        materializer.update(runtime.flow, deck: deck)
        let playlist = try XCTUnwrap(materializer.window(for: "Playlist")), library = try XCTUnwrap(materializer.window(for: "Library"))
        for window in [playlist, library] {
            XCTAssertTrue(screen.contains(window.frame), "\(window.title) \(window.frame) wholly on \(screen)")
            XCTAssertFalse(window.frame.intersects(deck.frame), "moved up onto the screen, it stands beside the deck, not on it")
        }
        XCTAssertFalse(playlist.frame.intersects(library.frame), "\(playlist.frame) apart from \(library.frame)")
    }

    func testTeardownLeavesTheDeck() throws {
        let (materializer, runtime) = try make(store())
        try waitForContent(materializer, runtime)
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        let window = try XCTUnwrap(materializer.window(for: "Speaker"))
        materializer.teardown()
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(window.delegate)
        XCTAssertTrue(materializer.materializedAuxiliaryWindows.isEmpty)
        XCTAssertTrue(deck.isVisible, "the deck is the controller's")
    }

    func testWhetherAFormWasShownIsKeptPerSkin() throws {
        let store = store()
        var (materializer, runtime) = try make(store)
        materializer.recordsVisibility = true
        runtime.state.script["Speaker"].visible = true
        materializer.update(runtime.flow, deck: deck)
        materializer.teardown()
        XCTAssertEqual(store.visibility, ["speaker": true])

        (materializer, runtime) = try make(store)
        defer { materializer.teardown() }
        var state = AIMPSkinState()
        materializer.restoreVisibility(of: runtime.skin, into: &state)
        XCTAssertEqual(state.script["Speaker"].visible, true, "seeded over the skin's InitialVisible")
        XCTAssertTrue(AIMPSkinStore(defaults: store.defaults).skin("Other").visibility.isEmpty, "another skin's are its own")
    }

    // MARK: - Helpers

    /// What is kept of the test skin, installed as "Test".
    private func store() -> AIMPSkinStore.Skin {
        AIMPSkinStore(defaults: scopedDefaults()).skin("Test")
    }

    private func make(_ store: AIMPSkinStore.Skin, docked: Bool = false, below: [String] = [])
        throws -> (AIMPSkinFormWindowMaterializer, AIMPSkinRuntime) {
        let skin = try Self.skin(docked: docked, below: below)
        let runtime = AIMPSkinRuntime(skin: skin, player: .probe, records: store)
        runtime.scripts.timing = .inline
        deckView.runtime = runtime
        let materializer = AIMPSkinFormWindowMaterializer()
        materializer.rebuild(runtime: runtime, like: deckView)
        return (materializer, runtime)
    }

    /// Every form's view has measured what it draws (off the main thread).
    private func waitForContent(_ materializer: AIMPSkinFormWindowMaterializer, _ runtime: AIMPSkinRuntime) throws {
        let measured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                materializer.menuItems(runtime.flow) { _, _ in }.count == runtime.skin.companions.count
            }
        }, object: nil)
        wait(for: [measured], timeout: 10)
    }

    /// A deck and a 40x30 speaker form, closed at first, left of the deck; `docked` puts it in a
    /// dock site on the deck instead. `below` adds 120x60 forms of those names the skin opens below
    /// the deck.
    private static func skin(docked: Bool, below: [String] = []) throws -> AIMPSkin {
        let site = docked ? #"<item class="LayoutDockSite" name="SpeakerSite"><properties><property name="Alignment" value="laRight"/><property name="ControlName" value="Speaker"/><property name="SizeMinimal" value="40,30"/></properties></item>"# : ""
        let main = """
        <layout><items>\(site)<item name="Deck"><properties><property name="Size" value="100,40"/>
          <property name="Color" value="-1"/></properties></item></items></layout>
        """
        let speaker = """
        <layout><items><item name="Cabinet"><properties><property name="Size" value="40,30"/>
          <property name="Color" value="-1"/></properties></item></items></layout>
        """
        let schema = """
        <schema><forms><form name="Speaker" master="AIMPMainForm"><properties><property name="InitialVisible" value="False"/>
          <property name="DisplayName" value="Speaker"/><property name="Placement" value="0" margins="0,0,0,0"/></properties></form>
          \(below.map { #"<form name="\#($0)" master="AIMPMainForm"><properties><property name="InitialVisible" value="False"/><property name="Placement" value="3" margins="0,0,0,0"/></properties></form>"# }.joined())
        </forms></schema>
        """
        let unit = """
        <layout><items><item name="Unit"><properties><property name="Size" value="120,60"/>
          <property name="Color" value="-1"/></properties></item></items></layout>
        """
        return try AIMPSkinLoader.load(data: project([("AIMPMainForm.xml", main), ("Schema.xml", schema), ("Speaker.xml", speaker)]
                                                     + below.map { ("\($0).xml", unit) }))
    }

    /// A project file (`ACSJ`) of `entries`.
    nonisolated static func project(_ entries: [(String, String)]) -> Data { AIMPTestProject.data(entries) }
}
