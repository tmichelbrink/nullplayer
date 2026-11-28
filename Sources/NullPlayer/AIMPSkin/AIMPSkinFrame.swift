import CoreGraphics
import Foundation

/// One drawn frame and what can be clicked on it.
struct AIMPSkinFrame: Sendable {
    let image: CGImage
    /// Topmost last, as drawn.
    let targets: [AIMPSkinTarget]
    /// The image's alpha: where the window is.
    var alpha: AIMPAlphaMask?
    /// Each shown control's tooltip (its `Hint`), topmost last.
    var hints: [(rect: CGRect, text: String)] = []
    /// Where each named item and control was drawn, for `IsActive` on the next frame.
    var namedRects: [String: CGRect] = [:]
    /// A control's `OnMouseEnter`, `OnMouseMove` and `OnMouseLeave` handlers, where it was drawn.
    struct MouseHandlers: Sendable {
        let name: String
        let rect: CGRect
        let enter: String?
        let move: String?
        let leave: String?
    }
    var mouseHandlers: [MouseHandlers] = []
    /// Each gauge's value this frame and how fast it may rise and fall toward it, in its units
    /// per thirtieth of a second.
    var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
    /// The quick search box's font, for the field the window types into over it.
    var searchFont: AIMPSkinFont?
    /// The items this layout hid (`AIMPSkinState.Script.autoHidden`), for the next frame's bindings.
    var autoHidden: Set<String> = []
    /// Pixels of `image` per skin pixel (the window's UI size times the screen's); every rect and
    /// point here is in skin pixels.
    var scale: CGFloat = 1

    func target(at point: CGPoint) -> AIMPSkinTarget? { AIMPSkinTarget.topmost(targets, at: point) }
    func hint(at point: CGPoint) -> String? { hints.last { $0.rect.contains(point) }?.text }

    /// Whether a pixel is part of the window: anything drawn there.
    func isOpaque(at point: CGPoint) -> Bool { alpha?.covers(Int(point.x * scale), Int(point.y * scale)) ?? false }

    /// What the frame draws, in skin pixels (`AIMPAlphaMask.drawnBounds`, which counts `image`'s).
    var drawnBounds: CGRect? {
        alpha?.drawnBounds.map {
            CGRect(x: ($0.minX / scale).rounded(.down), y: ($0.minY / scale).rounded(.down),
                   width: ($0.maxX / scale).rounded(.up) - ($0.minX / scale).rounded(.down),
                   height: ($0.maxY / scale).rounded(.up) - ($0.minY / scale).rounded(.down))
        }
    }

    /// `rect`, in skin pixels, as a rect of `image`.
    func imageRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
}
