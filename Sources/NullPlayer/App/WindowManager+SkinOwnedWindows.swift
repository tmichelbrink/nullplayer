import AppKit

extension WindowManager {
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
