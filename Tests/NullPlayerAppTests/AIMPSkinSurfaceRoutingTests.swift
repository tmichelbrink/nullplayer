import XCTest
@testable import NullPlayer

/// An AIMP skin's own playlist and library as the shared surface route sees them
/// (`SkinSurfaceRouter`): the skin draws those it has forms for, in a window or docked in the deck;
/// a show waits for the first skin; a skin switch carries whether each is open. Skins are
/// synthesized; nothing launches the app.
@MainActor
final class AIMPSkinSurfaceRoutingTests: XCTestCase {

    func testASkinDrawsTheListsItHasItsOwnOf() throws {
        let folder = try Self.temporaryFolder()
        let controller = AIMPSkinMainWindowController(importer: importer(folder), store: store())
        defer { controller.prepareForUITeardown() }
        for surface in SkinSurface.allCases {
            XCTAssertFalse(controller.drawsSurface(surface), "the unskinned panel draws none: \(surface)")
        }
        XCTAssertFalse(controller.deferUntilSkinLoads(.playlist) { XCTFail("held") }, "the panel is up")

        let url = folder.appendingPathComponent("Own Playlist.acs5")
        controller.present((try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist()), url), error: nil)
        XCTAssertTrue(controller.drawsSurface(.playlist))
        XCTAssertFalse(controller.drawsSurface(.library))
        XCTAssertFalse(controller.drawsSurface(.equalizer), "NullPlayer's EQ serves beside every skin")

        controller.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertTrue(controller.isShowingSurface(.playlist))
        controller.revealSurface(.playlist, toggle: false, restoredFrame: nil)
        XCTAssertTrue(controller.isShowingSurface(.playlist), "a show leaves it open")
        controller.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertFalse(controller.isShowingSurface(.playlist))
    }

    /// A playlist docked in the deck (Telos, Soot) is the skin's too: the route shows and hides it in
    /// place, and it never gets a window.
    func testADockedPlaylistIsRoutedInPlace() throws {
        let folder = try Self.temporaryFolder()
        let controller = AIMPSkinMainWindowController(importer: importer(folder), store: store())
        defer { controller.prepareForUITeardown() }
        let url = folder.appendingPathComponent("Docked Playlist.acs5")
        controller.present((try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist(docked: true)), url), error: nil)
        XCTAssertTrue(controller.drawsSurface(.playlist))
        controller.revealSurface(.playlist, toggle: false, restoredFrame: nil)
        XCTAssertTrue(controller.isShowingSurface(.playlist))
        controller.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertFalse(controller.isShowingSurface(.playlist))
        XCTAssertTrue(controller.managedSkinWindows.isEmpty)
    }

    /// A dock site reads visible only while it holds its form, docked and shown, as the layout
    /// draws it: Telos's `DockingState` counter watches its sites' `Visibility` to re-arrange its
    /// columns, so a playlist opened from the menu has to move it.
    func testADockSiteIsVisibleOnlyWhileItsFormShows() throws {
        let runtime = AIMPSkinRuntime(skin: try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist(docked: true)), player: .probe)
        runtime.state.script["PlaylistWindow"].visible = false
        XCTAssertEqual(runtime.flow.value("Site", "Visibility"), 0)
        runtime.state.script["PlaylistWindow"].visible = true
        XCTAssertEqual(runtime.flow.value("Site", "Visibility"), 1)
        runtime.state.script["PlaylistWindow"].docked = false
        XCTAssertEqual(runtime.flow.value("Site", "Visibility"), 0, "undocked, the form is in its own window")
    }

    /// A launch restores the playlist before the selected skin has loaded: the show waits for it,
    /// then runs once, after the skin is up. The equalizer never waits.
    func testAListShowWaitsForTheFirstSkin() throws {
        let folder = try Self.temporaryFolder()
        let importer = self.importer(folder)
        try Self.skinWithOwnPlaylist().write(to: folder.appendingPathComponent("Own Playlist.acs5"))
        importer.selection.select("Own Playlist")
        let controller = AIMPSkinMainWindowController(importer: importer, store: store())
        defer { controller.prepareForUITeardown() }

        var opened: [Bool] = []
        XCTAssertFalse(controller.deferUntilSkinLoads(.equalizer) { XCTFail("the EQ is NullPlayer's") })
        XCTAssertTrue(controller.deferUntilSkinLoads(.playlist) { opened.append(controller.drawsSurface(.playlist)) })
        XCTAssertEqual(opened, [])

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.loadedSkinURL != nil }, object: nil)
        wait(for: [loaded], timeout: 10)
        XCTAssertEqual(opened, [true], "replayed once, with the skin's own playlist to route to")
        XCTAssertFalse(controller.deferUntilSkinLoads(.playlist) { XCTFail("held") })
    }

    /// A skin switch neither opens nor closes the skin's own playlist; its window is the skin's,
    /// made only once wanted (the deck here is never on screen), and gone with it.
    func testASkinSwitchCarriesWhetherItsOwnPlaylistIsOpen() throws {
        let folder = try Self.temporaryFolder()
        let controller = AIMPSkinMainWindowController(importer: importer(folder), store: store())
        defer { controller.prepareForUITeardown() }
        let url = folder.appendingPathComponent("Own Playlist.acs5")
        func switchSkin() throws { controller.present((try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist()), url), error: nil) }

        // The carry reads the routed answer, which is `WindowManager`'s for its main window: here the
        // controller is not it, so the first skin starts closed, as NullPlayer's playlist is.
        try switchSkin()
        XCTAssertFalse(controller.isShowingSurface(.playlist), "the first skin carries NullPlayer's closed playlist")
        XCTAssertEqual(controller.managedSkinWindows.count, 0, "not wanted yet")

        controller.present(nil, error: nil)
        XCTAssertFalse(controller.drawsSurface(.playlist))
        XCTAssertEqual(controller.managedSkinWindows.count, 0, "gone with the skin")
    }

    // MARK: - Helpers

    private static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-own-windows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store() -> AIMPSkinStore {
        AIMPSkinStore(defaults: scopedDefaults())
    }

    private func importer(_ folder: URL) -> AIMPSkinImporter {
        AIMPSkinImporter(directoryURL: folder, defaults: scopedDefaults())
    }

    /// A project file (`ACSJ`): an empty main form, and a playlist window of the skin's own;
    /// `docked` puts the playlist in a dock site on the main form instead.
    nonisolated static func skinWithOwnPlaylist(docked: Bool = false) -> Data {
        let entries = [
            ("AIMPMainForm.xml", docked
                ? #"<layout><items><item class="LayoutDockSite" name="Site"><properties><property name="Alignment" value="laClient"/><property name="ControlName" value="PlaylistWindow"/></properties></item></items></layout>"#
                : #"<form name="AIMPMainForm"/>"#),
            ("Schema.xml", #"<schema><forms><form name="PlaylistWindow" master="AIMPMainForm"/></forms></schema>"#),
            ("PlaylistWindow.xml", #"<form name="PlaylistWindow"><control name="List" class="Playlist" link="Playlist"/></form>"#),
        ]
        return AIMPTestProject.data(entries)
    }
}
