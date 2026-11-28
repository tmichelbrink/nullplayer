import AppKit

/// NullPlayer's real library browser, inside the skin's library lists: one
/// `EmbeddedLibraryBrowserSurface` per skin session, as `.wal`'s component bridge keeps one
/// (`WinampModernComponentBridge.makeLibrarySurface`), so servers, tabs, search and history behave as
/// in NullPlayer's own library window. The skin draws the list area's fill and the chrome around it
/// (`AIMPSkinLayout.Look.libraryArea`); the browser sits over the area.
///
/// The one browser moves into whichever on-screen view reports a library area (the skin's library
/// window, the deck's lists, a docked library site) and leaves a view that stops reporting one. It
/// wears the skin's list colours (`AIMPSkinControl.Library`), through `SkinnedSurfaceStyle`'s
/// legibility rules; a skin that names none gets AIMP mode's own neutral style.
@MainActor
final class AIMPSkinLibraryHost {
    private var surface: EmbeddedLibraryBrowserSurface?
    /// The view the browser is in now.
    private weak var holder: AIMPSkinMainView?
    private var style: SkinnedSurfaceStyle?
    /// The style for a skin whose lists name no colours.
    private let fallbackStyle: SkinnedSurfaceStyle

    init(fallbackStyle: SkinnedSurfaceStyle) {
        self.fallbackStyle = fallbackStyle
    }

    /// The browser, while one is made.
    var browserView: NSView? { surface?.view }

    /// `view` laid its library lists out at `rect` (its own points; nil: it shows none now) in the
    /// skin's `colours`. A view that shows no area gives the browser up; one in a window that is not
    /// on screen does not take it from one that is, and a skin form's off-screen view never takes it.
    func libraryArea(_ rect: NSRect?, colours: AIMPSkinControl.Library?, in view: AIMPSkinMainView) {
        guard let rect, !rect.isEmpty, view.window != nil else {
            if holder === view { unmount() }
            return
        }
        if let holder, holder !== view, holder.window?.isVisible == true, view.window?.isVisible != true { return }
        // A skin form's view off screen (its window ordered out, or not shown yet) never takes it,
        // even with no holder: the browser would sit in a window no one sees. It reports again as its
        // window shows (`AIMPSkinFormWindowMaterializer.update`).
        if holder !== view, !view.drawsWithoutWindow, view.window?.isVisible != true { return }
        let surface = self.surface ?? make(scaledBy: view)
        if surface.view.superview !== view {
            surface.unmountFromHolder()
            view.addSubview(surface.view)
            holder = view
        }
        surface.view.frame = rect
        surface.applyContentScale(view.uiScale)
        surface.applyRowPadding(Self.rowPadding(view.skinState))
        let style = colours.map { Self.style($0, over: fallbackStyle) } ?? fallbackStyle
        if style != self.style {
            self.style = style
            surface.applyStyle(style)
        }
    }

    /// The row spacing a skin's script gave its library table (BECHA, Vilma and the other Zigar-style
    /// decks' row-spacing key: `Style.RowContentOffsets.Top`/`Bottom` 8, 4 or 2 on `MLTable`): the
    /// points past the 2 + 2 the browser's own rows already leave. None set: the browser's own.
    nonisolated static func rowPadding(_ state: AIMPSkinState) -> CGFloat {
        guard let offsets = state.libraryRowOffsets else { return 0 }
        return CGFloat(max(0, offsets.top + offsets.bottom - 4))
    }

    /// The skin is going: the browser goes with it, its server work cancelled.
    func teardown() {
        surface?.prepareForUITeardown()
        surface = nil
        holder = nil
        style = nil
    }

    /// `view`'s window went off screen: the browser leaves it, if it was there. True when it was, so
    /// the views still on screen report their areas again and one takes it.
    @discardableResult
    func release(from view: AIMPSkinMainView) -> Bool {
        guard holder === view else { return false }
        unmount()
        return true
    }

    private func unmount() {
        surface?.unmountFromHolder()
        holder = nil
    }

    private func make(scaledBy view: AIMPSkinMainView) -> EmbeddedLibraryBrowserSurface {
        let surface = EmbeddedLibraryBrowserSurface(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            contentScaleFallback: { [weak view] in view?.uiScale ?? 1 },
            presentLinkSheet: { [weak self] in self?.presentLinkSheet() })
        self.surface = surface
        return surface
    }

    /// The Plex link sheet, on the window the browser is in, as `WindowManager.showPlexLinkSheet`
    /// shows it on NullPlayer's.
    private func presentLinkSheet() {
        guard let window = holder?.window else { return }
        PlexLinkSheet().showAsSheet(from: window) { [weak self] linked in
            if linked { self?.surface?.reloadData() }
        }
    }

    /// The skin's list colours as the browser's roles: its fill the background, its row text the
    /// text and the accent (source, chosen tab, index letters), its selected row's fill and text the
    /// selection; whatever it leaves out from `fallback`. The selected text is made for its row's
    /// fill, not the list's: AIMP Modern v3.63's light blue, an accent on its blue list, was hard to read.
    static func style(_ colours: AIMPSkinControl.Library, over fallback: SkinnedSurfaceStyle) -> SkinnedSurfaceStyle {
        let background = colours.fill.flatMap(color) ?? fallback.background
        let text = colours.rowText.flatMap(color) ?? fallback.text
        let selection = colours.selected.flatMap(color) ?? fallback.selectionBackground
        let selectionText = colours.selectedText.flatMap(color) ?? fallback.selectionText
        return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: background, text: text, currentText: text, selectionBackground: selection,
            selectionText: selectionText, treeText: text, treeSelection: selection))
    }

    /// An AIMP colour (`0xAARRGGBB`).
    private static func color(_ argb: UInt32) -> NSColor? { NSColor(cgColor: AIMPSkinText.color(argb)) }
}
