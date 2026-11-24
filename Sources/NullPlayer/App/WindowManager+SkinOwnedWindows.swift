import AppKit

/// A main window whose skin opens top-level windows of its own beside the player: a `.wmz` skin's
/// `theme.openView` panels, a `.wal` skin's containers and hosted windows, an AIMP skin's forms
/// (speakers, an amplifier, the skin's playlist). `WindowManager` manages them, raises them with
/// the player and re-places them on Snap To Default through this, without a branch per family.
protocol SkinOwnedWindowsProviding: MainWindowProviding {
    /// The skin's windows open now, in the order they are raised.
    var skinOwnedWindows: [NSWindow] { get }
    /// How `WindowManager` manages each of them (`managedWindowRecords`).
    var managedSkinWindows: [ManagedSkinWindow] { get }
}

/// One of a skin's own windows as `WindowManager` manages it: in the centre stack or not, a snap
/// target or not.
struct ManagedSkinWindow {
    let window: NSWindow
    var centerStack = false
    var snapTarget = true
}

extension SkinOwnedWindowsProviding {
    /// Snap targets only, never centre-stack members: an arbitrary authored canvas (Halo 2's `.wmz`
    /// panels are 406x209 against a 327x294 player) has no column to join.
    var managedSkinWindows: [ManagedSkinWindow] { skinOwnedWindows.map { ManagedSkinWindow(window: $0) } }
}

extension WMPMainWindowController: SkinOwnedWindowsProviding {
    var skinOwnedWindows: [NSWindow] { materializedAuxiliaryWindows }
}

extension WinampModernMainWindowController: SkinOwnedWindowsProviding {
    /// A `newDynamicContainer` copy (B110) is still managed — levels, minimize — but is not a snap
    /// target: it is a frame glued to another window's rect. A hosted window joins the centre stack
    /// as its definition says.
    var managedSkinWindows: [ManagedSkinWindow] {
        let instances = Set(dynamicInstanceAuxiliaryWindows.map(ObjectIdentifier.init))
        return materializedAuxiliaryWindows.map { ManagedSkinWindow(window: $0, snapTarget: !instances.contains(ObjectIdentifier($0))) }
            + materializedHostedWindows.map {
                ManagedSkinWindow(window: $0.window, centerStack: $0.id.definition.stackPolicy.participatesInCenterStack)
            }
    }
}

extension WindowManager {
    /// The main window, when its skin opens windows of its own.
    var skinOwnedWindowsProvider: SkinOwnedWindowsProviding? {
        mainWindowController as? SkinOwnedWindowsProviding
    }

    /// Keeps what hangs under `window` attached after it changed size in place: every snap target
    /// docked below `oldFrame` moves by however far the window's bottom edge moved. For a skin window
    /// that grows or shrinks itself with its top-left held (a panel opening in the skin); a programmatic
    /// move, so it runs under `isSnappingWindow` and never starts a group drag.
    func carryWindowsDockedBelow(_ window: NSWindow, from oldFrame: NSRect) {
        let deltaY = window.frame.minY - oldFrame.minY
        guard deltaY != 0 else { return }
        let others = snapTargetWindows().filter { $0 !== window }
        let docked = Self.windowsDocked(below: oldFrame, among: others, threshold: dockThreshold)
        guard !docked.isEmpty else { return }

        isSnappingWindow = true
        defer { isSnappingWindow = false }
        for win in docked {
            var frame = win.frame
            frame.origin.y += deltaY
            win.setFrame(frame, display: true, animate: false)
        }
        postLayoutChangeNotification()
    }
}
