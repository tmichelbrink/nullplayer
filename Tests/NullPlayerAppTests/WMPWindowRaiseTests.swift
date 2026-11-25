import AppKit
import XCTest
@testable import NullPlayer

/// **W273 — clicking one window raises all of them, a `.wmz` skin's own panels included.**
///
/// `bringAllWindowsToFront` raises a fixed list of NullPlayer's controllers, and a skin's
/// `theme.openView` panels are not controllers, so clicking the player left `WoW`'s EQ, vis and info
/// panels behind whatever other app covered them. The list is shared by every mode, so the panels
/// join it only where the main window has windows of its own (`SkinOwnedWindowsProviding`: `.wmz`,
/// `.wal`, AIMP), and every other mode must raise exactly what it did before.
///
/// The ordering itself — deferred a turn, `orderFrontRegardless` — needs a window server and was
/// verified live; `wmp-skin-guide/reference/windows/placement.md` § *Raising the skin's windows together*.
@MainActor
final class WMPWindowRaiseTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
                 backing: .buffered, defer: true)
    }

    /// A skin's windows follow the app's, in order; a mode with none (`skinWindows` nil, its main
    /// window no `SkinOwnedWindowsProviding`) raises exactly the app's own windows.
    func testOnlyWMPWinampModernAndAIMPAppendTheSkinsWindows() {
        let player = window(), equalizer = window()
        let appWindows: [NSWindow?] = [player, nil, equalizer]
        let panels = [window(), window()]
        let ids = { (windows: [NSWindow?]) in windows.map { $0.map(ObjectIdentifier.init) } }

        XCTAssertEqual(ids(WindowManager.raiseOrder(appWindows, skinWindows: panels)), ids(appWindows + panels.map { $0 }),
                       "the skin's windows follow the app's windows, in order")
        XCTAssertEqual(ids(WindowManager.raiseOrder(appWindows, skinWindows: nil)), ids(appWindows),
                       "a mode without a skin's own windows raises exactly the app's own windows")

        let providing: [(AnyClass, Bool)] = [(WMPMainWindowController.self, true), (WinampModernMainWindowController.self, true),
                                             (AIMPSkinMainWindowController.self, true), (MainWindowController.self, false),
                                             (ModernMainWindowController.self, false)]
        for (type, provides) in providing {
            XCTAssertEqual(type is SkinOwnedWindowsProviding.Type, provides, "\(type)")
        }
    }
}
