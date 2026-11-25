import XCTest
@testable import NullPlayer

/// The skin's library lists are NullPlayer's library browser (`AIMPSkinLibraryHost`): one area over
/// the tree and table, the browser mounted there at the view's scale, taking the clicks, in the
/// lists' colours, and gone with the skin. Skins are synthesized.
@MainActor
final class AIMPSkinLibraryHostTests: XCTestCase {
    func testTheBrowserFillsTheListsAreaAndTakesItsClicks() throws {
        let (window, view, host) = try make()
        defer { host.teardown(); window.orderOut(nil) }

        let browser = try XCTUnwrap(host.browserView, "mounted once the lists were drawn")
        XCTAssertTrue(browser.superview === view)
        // The tree (0,0 80x100) and the table (80,0 120x100) as one area, cut to the 360x96 the form
        // shows, at the view's scale of 2.
        XCTAssertEqual(view.displaySize, CGSize(width: 360, height: 96))
        XCTAssertEqual(browser.frame, NSRect(x: 0, y: 0, width: 400, height: 192))
        XCTAssertTrue(view.hitTest(NSPoint(x: 100, y: 100))?.isDescendant(of: browser) == true, "the browser takes its clicks")
        XCTAssertFalse(view.hitTest(NSPoint(x: 500, y: 100))?.isDescendant(of: browser) == true, "beside the lists is the skin's")

        view.setFrameSize(NSSize(width: 360, height: 96))
        XCTAssertEqual(browser.frame, NSRect(x: 0, y: 0, width: 200, height: 96), "follows the view's size")

        host.teardown()
        XCTAssertNil(host.browserView)
        XCTAssertNil(browser.superview, "gone with the skin")
    }

    func testTheBrowserWearsTheListsColours() throws {
        let (window, view, host) = try make()
        defer { host.teardown(); window.orderOut(nil) }
        let colours = try XCTUnwrap(view.drawnFrame?.targets.lazy.compactMap { target -> AIMPSkinControl.Library? in
            if case .libraryArea(let colours) = target.kind { return colours } else { return nil }
        }.first)
        XCTAssertEqual(colours.fill, 0xFF10_2030)
        let fallback = AIMPSkinMainWindowController.unskinnedSurfaceStyle
        let style = AIMPSkinLibraryHost.style(colours, over: fallback)
        XCTAssertEqual(style.background.usingColorSpace(.sRGB)?.redComponent ?? 0, CGFloat(0x10) / 255, accuracy: 0.01)
        XCTAssertEqual(style.selectionBackground.usingColorSpace(.sRGB)?.blueComponent ?? 0, CGFloat(0x80) / 255, accuracy: 0.01)
        let unstyled = AIMPSkinLibraryHost.style(AIMPSkinControl.Library([:]), over: fallback)
        XCTAssertEqual(unstyled.background, fallback.background, "a skin naming no colours wears AIMP mode's own")
    }

    // MARK: - Helpers

    private func make() throws -> (NSWindow, AIMPSkinMainView, AIMPSkinLibraryHost) {
        let window = SkinnedBorderlessWindow(contentRect: NSRect(x: 300, y: 300, width: 400, height: 240),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = AIMPSkinMainView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        window.contentView = view
        window.orderFront(nil)
        let host = AIMPSkinLibraryHost(fallbackStyle: AIMPSkinMainWindowController.unskinnedSurfaceStyle)
        view.onLibraryArea = { view, rect, colours in host.libraryArea(rect, colours: colours, in: view) }
        view.uiScale = 2
        view.scheduler.timing = .probe(clock: nil)
        let runtime = AIMPSkinRuntime(skin: try Self.skin(), player: .probe)
        runtime.scripts.timing = .inline
        view.runtime = runtime
        // Sized as the window controller fits it: the form at the UI scale.
        view.setFrameSize(NSSize(width: view.displaySize.width * 2, height: view.displaySize.height * 2))
        return (window, view, host)
    }

    /// A main form with a library tree and table side by side, 200x100, in the skin's list colours.
    static func skin() throws -> AIMPSkin {
        let style = """
        <property name="StyleContent"><property name="ColorContent" value="4279246896"/>
          <property name="RowColorSelected" value="4278190208"/><property name="RowColorText" value="4294967295"/></property>
        """
        let main = """
        <layout><items><item name="Face"><properties><property name="Size" value="200,120"/><property name="Color" value="-1"/></properties>
          <controls>
            <control link="MLGroupingTree"><properties><property name="PlaceInfo" anchors="1,1,0,0" margins="0,0,0,0" Size="80,100"/>\(style)</properties></control>
            <control link="MLTable"><properties><property name="PlaceInfo" anchors="1,1,0,0" margins="80,0,0,0" Size="120,100"/>\(style)</properties></control>
          </controls></item></items></layout>
        """
        return try AIMPSkinLoader.load(data: AIMPSkinFormWindowMaterializerTests.project([("AIMPMainForm.xml", main)]))
    }
}
