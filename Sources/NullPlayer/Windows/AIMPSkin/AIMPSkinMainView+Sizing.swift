import AppKit

extension AIMPSkinMainView {
    // MARK: - Sizing

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let edge = sizing.edge.map({ $0 * uiScale }) else { return }
        // A view of fixed width sizes only down (Bento's basic view).
        guard sizing.fixedWidth == nil else {
            addCursorRect(NSRect(x: 0, y: bounds.maxY - edge, width: bounds.width, height: edge), cursor: .resizeUpDown)
            return
        }
        addCursorRect(NSRect(x: bounds.maxX - edge, y: 0, width: edge, height: bounds.height - edge), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - edge, width: bounds.width - edge, height: edge), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: bounds.maxX - edge, y: bounds.maxY - edge, width: edge, height: edge),
                      cursor: .diagonalResize(top: false, left: false))
    }

    /// Follows a sizing drag: the window grows from its top-left corner, never below the form's
    /// natural size; the redraw's measure refits it.
    func resize() {
        guard let size = sizing.dragged(to: NSEvent.mouseLocation, scale: uiScale) else { return }
        search.end()
        sizing.canvas = size
        invalidateContent()
        renderNow()
    }

    /// A sizing drag ended: the size it left is kept for the skin.
    func endResize() {
        sizing.drag = nil
        keep(sizing.canvas)
    }

    /// A sizable window fills its screen's visible area from its top-left corner, and back.
    func toggleMaximized() {
        guard sizing.edge != nil, let window, let screen = window.screen?.visibleFrame else { return }
        search.end()
        sizing.toggleMaximized(screen: screen.size, scale: uiScale)
        invalidateContent()
        renderNow()
        if sizing.unmaximized != nil { window.setFrameTopLeftPoint(NSPoint(x: screen.minX, y: screen.maxY)) }
        keep(sizing.unmaximized ?? sizing.canvas)
    }

    /// A fixed window refits after an item is shown or hidden (Cassette-3D's VU meter panel): it
    /// grows to hold what is now shown, and back.
    func refitShownItems() {
        let before = sizing.canvas
        sizing.fit(runtime?.skin, form: formName, state: skinState)
        guard sizing.canvas != before else { return }
        invalidateContent()
        renderNow()
    }

    /// A sizable window takes the size of the view a page turn showed (Bento's basic and advanced
    /// views), the window's top-left corner kept.
    func refitPages() {
        guard sizing.refitPages(runtime?.skin, form: formName, state: skinState) else { return }
        window?.invalidateCursorRects(for: self)
        invalidateContent()
        renderNow()
    }

    /// The size the next load of this skin's form starts at.
    private func keep(_ size: CGSize) {
        guard let skin = runtime?.skin else { return }
        AIMPSkinSizing.save(size, skin: skin, form: formName)
    }
}
