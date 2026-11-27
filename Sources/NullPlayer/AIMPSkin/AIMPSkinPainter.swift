import CoreGraphics
import Foundation

/// Draws a laid-out frame (`AIMPSkinLayout`) as AIMP does, in two passes over the tree: every
/// item's picture, then every control, an item's own before its children's. A parent's control lies
/// under its children's (the Mayaks' meter glass under their level bars) and over their pictures
/// (Kenwood KX-800's keys). Each control draws as the layout decided it looks (`Look`), on a
/// canvas of drawing primitives (`AIMPSkinCanvas`); what the frame offers the pointer is read from
/// the tree, not from drawing.
final class AIMPSkinPainter {
    let flow: AIMPSkinDataflow
    let canvas: AIMPSkinCanvas
    var context: CGContext { canvas.context }
    var host: AIMPSkinHostState { flow.host }

    init(flow: AIMPSkinDataflow, context: CGContext) {
        self.flow = flow
        canvas = AIMPSkinCanvas(context: context, clock: flow.host.feedback.clock, fonts: flow.skin.fontShelf)
    }

    func image(_ reference: String?) -> AIMPSkinImage? { flow.image(reference) }

    func paint(_ image: AIMPSkinImage?, in rect: CGRect, frame: Int = 0) { canvas.paint(image, in: rect, frame: frame) }

    /// A control's or item's colour as ARGB, through the resource aliases a script repointed.
    func argb(_ color: AIMPSkinColor?) -> UInt32? { flow.color(color) }

    /// A font as drawn, through the resources a script repointed (`AIMPSkinFont.resolved`).
    func font(_ font: AIMPSkinFont) -> AIMPSkinFont {
        font.resolved(in: flow.skin.resources, links: flow.state.script.resourceLinks)
    }

    /// What a pass over the item tree draws.
    enum Layer { case pictures, controls }

    /// Draws `tree` in both passes; `asItem`: its root is an item of the form, drawn with its own
    /// picture, rather than the form itself.
    func paint(_ tree: AIMPSkinLayout.Item, asItem: Bool) {
        for layer in [Layer.pictures, .controls] {
            if asItem { item(tree, layer) } else { children(of: tree, layer) }
        }
    }

    private func item(_ placed: AIMPSkinLayout.Item, _ layer: Layer) {
        let item = placed.item, rect = placed.rect, shown = placed.visible ?? rect
        if AIMPSkinTrace.items { print("  ITEM \(item.name ?? "?") \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))") }
        if layer == .pictures {
            // A scroll view's own picture stays put under what scrolls.
            canvas.fill(shown, argb: argb(item.color))
            paint(image(item.texture), in: shown)
        }
        // A dock site keeps the form it holds inside it (`AIMPSkinDockSites`); a scroll view shows
        // what it holds within its own rect.
        guard item.isDockSite || placed.visible != nil else { return children(of: placed, layer) }
        context.saveGState()
        context.clip(to: shown)
        children(of: placed, layer)
        context.restoreGState()
    }

    private func children(of placed: AIMPSkinLayout.Item, _ layer: Layer) {
        if layer == .controls {
            for control in placed.controls {
                if let cut = control.cut { context.saveGState(); context.clip(to: cut) }
                self.control(control)
                if control.cut != nil { context.restoreGState() }
            }
        }
        for child in placed.items { item(child, layer) }
    }

    /// A control, then the controls nested in it, inside its opacity, blend and mask.
    private func control(_ placed: AIMPSkinLayout.Control) {
        let control = placed.control
        // A lamp a script fades with the music, children and all, else the opacity the skin gives it
        // (`BlendingModeOpacity`, 0–255: Soot's 0 over its swipe surfaces, 75 corpus skins' dimmed
        // labels); a layer blended over what is under it (Koyna RN's spectrum: a screened copy and
        // a differenced one, a pixel apart).
        var opacity = control.name.flatMap { flow.state.animation[$0].opacity } ?? control.opacity
        // A control NullPlayer cannot act on is dimmed (`AIMPSkinLayout.unavailable`).
        if placed.unavailable { opacity = (opacity ?? 255) * 0.6 }
        let blend = control.blend
        if opacity != nil || blend != nil {
            context.saveGState()
            if let opacity { context.setAlpha(CGFloat(opacity / 255)) }
            if let blend { context.setBlendMode(blend) }
        }
        defer { if opacity != nil || blend != nil { context.restoreGState() } }
        let masked = clipToMask(placed)
        defer { if masked { context.restoreGState() } }
        draw(placed)
        if AIMPSkinTrace.items {
            let rect = placed.rect
            let links = control.bindings.links.map {
                "\($0.target ?? "?")<-\($0.source ?? "?").\($0.pin ?? "?")\($0.expression.map { "[\($0)]" } ?? "")"
            }
            print("  CONTROL \(control.name ?? "?") \(control.className ?? "?") \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)) \(links.joined(separator: " "))")
        }
        for child in placed.controls {
            if let cut = child.cut { context.saveGState(); context.clip(to: cut) }
            self.control(child)
            if child.cut != nil { context.restoreGState() }
        }
    }

    /// A control whose picture names a mask frame shows itself and the controls in it only inside
    /// that frame's shape: A4's keys are their state's fill seen through a play or pause glyph (133
    /// corpus skins). Cover art and glass use their masks themselves. True when it clipped (the
    /// caller restores).
    private func clipToMask(_ placed: AIMPSkinLayout.Control) -> Bool {
        switch placed.look {
        case .coverArt, .glass: return false
        default: break
        }
        guard let frame = placed.control.maskFrame, let picture = placed.image, picture.hasPixels else { return false }
        let rect = placed.placed.standardized.integral
        // The mask frame filled as the picture fills (centred glyphs stay their size).
        guard rect.width > 0, rect.height > 0, let mask = AIMPSkinCanvas.mask(picture, frame: frame, size: rect.size) else { return false }
        context.saveGState()
        canvas.clip(to: rect, mask: mask)
        return true
    }

    /// One shown control where the layout put it, as it decided it looks.
    private func draw(_ placed: AIMPSkinLayout.Control) {
        let control = placed.control, rect = placed.rect, image = placed.image
        // A mirrored control (Akai GX-R60's right reel: the left's strip, flipped and run backwards,
        // so both turn the same way).
        let flipX = control.flipX, flipY = control.flipY
        if flipX || flipY {
            context.saveGState()
            context.translateBy(x: flipX ? rect.minX + rect.maxX : 0, y: flipY ? rect.minY + rect.maxY : 0)
            context.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
        }
        defer { if flipX || flipY { context.restoreGState() } }
        switch placed.look {
        case .key(let key, let frame, let caption, let glyphFirst):
            drawKey(control, key, image: image, frame: frame, caption: caption, glyphFirst: glyphFirst, in: rect)
        case .picture: paint(image, in: rect)
        case .frame(let frame): paint(image, in: rect, frame: frame)
        case .digits(let value, let digits): drawDigits(image, value: value, digits: digits, in: rect)
        case .time(let seconds, let digits): drawTime(image, seconds: seconds, digits: digits, in: rect)
        case .slider(let slider, let fraction, let thumb): drawSlider(slider, image: image, fraction: fraction, thumb: thumb, in: rect)
        case .rating(let rating): drawRating(image, rating: rating, in: rect)
        case .pageSelector(let count, let shown): drawPageSelector(image, count: count, shown: shown, in: rect)
        case .playlist(let style, let rows, let shown, let headers):
            paint(image, in: rect)
            drawPlaylist(style, rows: rows, shown: shown, headers: headers, in: rect)
        case .libraryArea(let fill):
            paint(image, in: rect)
            canvas.fill(rect, argb: fill)
        case .scrollBar(let thumb, let length, let share):
            paint(image, in: rect)
            guard let thumb, let share else { return }
            paint(thumb, in: CGRect(x: rect.minX, y: rect.minY + ((rect.height - length) * share).rounded(), width: rect.width, height: length))
        case .search(let text, let font):
            // The search typed so far over its box (while the window's field types over it, the field shows it).
            paint(image, in: rect)
            if let text { canvas.draw(text, font: self.font(font), at: CGPoint(x: rect.minX + 4, y: rect.midY), centeredIn: nil, clippedTo: rect) }
        case .tabControl(let tabs, let caption): drawTabControl(tabs, caption: caption, image: image, in: rect)
        case .playlistTabs(let tabs, let playing): drawPlaylistTabs(tabs, playing: playing, image: image, in: rect)
        case .playlistBox(let font, let centred):
            // The playlist chooser: NullPlayer has the one playlist.
            paint(image, in: rect)
            if let font {
                canvas.draw(AIMPSkinList.playlistName, font: self.font(font), at: CGPoint(x: rect.minX + 4, y: rect.midY), centeredIn: centred ? rect : nil, clippedTo: rect)
            }
        case .equalizer(let preamp, let curve): drawEqualizer(preamp: preamp, curve: curve, image: image, in: rect)
        case .coverArt(let cover): drawCoverArt(cover, mask: control.maskFrame, image: image, in: rect)
        case .glass(let blur, let tint): drawBlurredGlass(blur: blur, tint: tint, mask: control.maskFrame, image: image, in: rect)
        case .waveform(let peaks, let played, let background, let content, let rest, let thumb):
            canvas.fill(rect, argb: background)
            paint(image, in: rect)
            drawWaveform(peaks, played: played, content: content ?? 0xFFFF_FFFF, rest: rest, in: rect)
            if let thumb, thumb.hasPixels {
                let size = thumb.frameSize, x = (rect.minX + rect.width * CGFloat(min(1, max(0, played))) - size.width / 2).rounded()
                paint(thumb, in: CGRect(x: x, y: rect.minY, width: max(1, size.width), height: rect.height), frame: thumb.frameCount - 1)
            }
        // AIMP's oscilloscope (the GX-F90's WAVE page, TEAC CD-RW890's two channels): NullPlayer has
        // the spectrum, not the samples, so the trace is its bands as waves, as loud as the output.
        case .waveForm(let trace): drawWaveForm(trace, image: image, in: rect)
        case .visualization(let spectrum, let cover):
            // AIMP's visualization paints its whole box over whatever the skin put behind it for when
            // none runs (RealPlayer 11's "NO VISUAL" picture, the display's own picture: Red Bias
            // 2.0's logo, Hameleon's AIMP 2 logo); with none running, that shows. Only its
            // `CoverFrame` lies over it (RealPlayer's gloss).
            let mode = flow.state.script.visualMode
            if mode != .off {
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(rect)
                switch mode {
                case .spectrum: drawSpectrum(spectrum, in: rect.insetBy(dx: 4, dy: 4))
                case .scope: drawWaveForm(AIMPControlClass.Trace(color: argb(spectrum.color), channel: nil), image: nil, in: rect)
                case .vu: drawMeters(in: rect, id: control.id)
                case .off: break
                }
            }
            if let cover, cover >= 0 { paint(image, in: rect, frame: cover) }
        case .spectrum(let spectrum): drawSpectrum(spectrum, in: rect)
        }
    }
}
