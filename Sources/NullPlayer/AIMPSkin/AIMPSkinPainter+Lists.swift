import CoreGraphics
import CoreText
import Foundation

extension AIMPSkinPainter {
    /// NullPlayer's playlist in the skin's colours and fonts: a row per track, its number and title
    /// left, its length right; the playing row and the selected one lit. `shown` are the rows the
    /// quick search leaves, `rows` those in view (`AIMPSkinLayout.Look.playlist`).
    func drawPlaylist(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int], in rect: CGRect) {
        // Its own background picture (GX-77's paper sheet), else its background colour.
        if let picture = image(style.picture), picture.hasPixels {
            paint(picture, in: rect)
        } else {
            canvas.fill(rect, argb: argb(style.background))
        }
        let lists = flow.state.lists, rowPicture = image(style.rowPicture).flatMap { $0.hasPixels ? $0 : nil }
        context.saveGState()
        context.clip(to: rect)
        for (offset, index) in rows.inView(shown).enumerated() {
            let row = host.player.playlist.rows[index]
            let line = rows.line(offset, in: rect)
            let playing = index == host.player.playlistIndex, selected = lists.playlistSelection.contains(index)
            let state: AIMPSkinControl.Playlist.Row = playing && selected ? .playingSelected : playing ? .playing : selected ? .selected : .normal
            if let rowPicture { paint(rowPicture, in: line) }
            canvas.fill(line, argb: argb(style.fills[state]))
            guard let font = style.fonts[state].map({ self.font($0) }) else { continue }
            let time = row.seconds > 0 ? String(format: "%d:%02d", row.seconds / 60, row.seconds % 60) : ""
            let timeWidth = CGFloat(time.count) * CGFloat(font.height) * 0.55 + 6
            canvas.draw(time, font: font, at: CGPoint(x: line.maxX - timeWidth, y: line.midY), centeredIn: nil, clippedTo: line)
            canvas.draw("\(index + 1). \(row.title)", font: font, at: CGPoint(x: line.minX + 3, y: line.midY), centeredIn: nil,
                 clippedTo: CGRect(x: line.minX, y: line.minY, width: max(0, line.width - timeWidth - 4), height: line.height))
        }
        context.restoreGState()
    }
}
