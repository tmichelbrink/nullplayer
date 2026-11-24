import CoreGraphics
import CoreText
import Foundation

extension AIMPSkinPainter {
    /// NullPlayer's playlist in the skin's colours and fonts, as AIMP lays its list out: a header over
    /// each group (its expand button, switch, name, and its tracks' count and length), then each
    /// track on two lines, its switch, number, title and length, its format and size under the title
    /// with its rating marks at the right; the playing row and the selected one lit. AIMP 2's list
    /// (`classic`) is one line a track. `shown` are the rows the quick search leaves, `rows` those
    /// in view (`AIMPSkinLayout.Look.playlist`).
    func drawPlaylist(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int], in rect: CGRect) {
        // Its own background picture (GX-77's paper sheet), else its background colour.
        if let picture = image(style.picture), picture.hasPixels {
            paint(picture, in: rect)
        } else {
            canvas.fill(rect, argb: argb(style.background))
        }
        let tracks = host.player.playlist.rows
        let lists = flow.state.lists, rowPicture = image(style.rowPicture).flatMap { $0.hasPixels ? $0 : nil }
        let drawn = { (name: String?) in self.image(name).flatMap { $0.hasPixels ? $0 : nil } }
        let expand = style.classic ? nil : drawn(style.expandButtons)
        let switches = style.classic ? nil : drawn(style.switches)
        let headerSwitches = style.classic ? nil : drawn(style.headerSwitches)
        let marks = style.classic ? nil : drawn(style.marks)
        // The switches stand in a column after the expand buttons'; the text after them.
        let switchX = rect.minX + 3 + (expand.map { $0.frameSize.width + 3 } ?? 0)
        let textX = switchX + (switches.map { $0.frameSize.width + 4 } ?? 0)
        context.saveGState()
        context.clip(to: rect)
        for slot in rows.slots {
            let index = shown[slot.row], row = tracks[index]
            if slot.header > 0 {
                drawGroupHeader(row.group, style: style, tracks: tracks, expand: expand, switches: headerSwitches ?? switches, switchX: switchX,
                                textX: textX, in: CGRect(x: rect.minX, y: rect.minY + slot.top, width: rect.width, height: slot.header))
            }
            let line = CGRect(x: rect.minX, y: rect.minY + slot.top + slot.header, width: rect.width, height: slot.height - slot.header)
            let playing = index == host.player.playlistIndex, selected = lists.playlistSelection.contains(index)
            let state: AIMPSkinControl.Playlist.Row = playing && selected ? .playingSelected : playing ? .playing : selected ? .selected : .normal
            if let rowPicture { paint(rowPicture, in: line) }
            let lit = style.classic ? line : CGRect(x: textX - 2, y: line.minY, width: max(0, line.maxX - textX + 2), height: line.height)
            canvas.fill(lit, argb: argb(style.fills[state]))
            guard let font = style.fonts[state].map({ self.font($0) }) else { continue }
            let time = row.seconds > 0 ? String(format: "%d:%02d", row.seconds / 60, row.seconds % 60) : ""
            let timeWidth = CGFloat(time.count) * CGFloat(font.height) * 0.55 + 6
            if style.classic {
                canvas.draw(time, font: font, at: CGPoint(x: line.maxX - timeWidth, y: line.midY), centeredIn: nil, clippedTo: line)
                canvas.draw("\(index + 1). \(row.title)", font: font, at: CGPoint(x: line.minX + 3, y: line.midY), centeredIn: nil,
                            clippedTo: CGRect(x: line.minX, y: line.minY, width: max(0, line.width - timeWidth - 4), height: line.height))
                continue
            }
            let detail = style.detailFonts[state].map { self.font($0) } ?? font
            let first = line.minY + 4 + CGFloat(font.height) / 2
            let second = line.minY + 4 + CGFloat(font.height) + 2 + CGFloat(detail.height) / 2
            if let switches {
                let size = switches.frameSize
                paint(switches, in: CGRect(x: switchX, y: (first - size.height / 2).rounded(), width: size.width, height: size.height))
            }
            // The number, the title after it, and the details under the title.
            let number = "\(index + 1). "
            let titleX = textX + AIMPSkinText.width(number, font: font)
            canvas.draw(time, font: font, at: CGPoint(x: line.maxX - timeWidth, y: first), centeredIn: nil, clippedTo: line)
            let room = CGRect(x: textX, y: line.minY, width: max(0, line.maxX - timeWidth - 4 - textX), height: line.height)
            canvas.draw(number + row.title, font: font, at: CGPoint(x: textX, y: first), centeredIn: nil, clippedTo: room)
            // The rating's five marks at the right of the second line; NullPlayer's rows carry none.
            var detailRight = line.maxX - 4
            if let marks {
                let size = marks.frameSize
                for mark in 0..<5 {
                    let x = line.maxX - 6 - CGFloat(5 - mark) * size.width
                    paint(marks, in: CGRect(x: x, y: (second - size.height / 2).rounded(), width: size.width, height: size.height))
                }
                detailRight = line.maxX - 10 - 5 * size.width
            }
            canvas.draw(row.details, font: detail, at: CGPoint(x: titleX, y: second), centeredIn: nil,
                        clippedTo: CGRect(x: titleX, y: line.minY, width: max(0, detailRight - titleX), height: line.height))
        }
        context.restoreGState()
    }

    /// A group's header: its picture (else a rule under it in the header's colour), its expand
    /// button shown open, its switch, its name, and at the right its tracks' count and length
    /// (`24 / 1:35:02`).
    private func drawGroupHeader(_ group: String, style: AIMPSkinControl.Playlist, tracks: [AIMPSkinPlayerSnapshot.Playlist.Row],
                                 expand: AIMPSkinImage?, switches: AIMPSkinImage?, switchX: CGFloat, textX: CGFloat, in band: CGRect) {
        let font = self.font(style.headerFont)
        if let picture = image(style.headerPicture), picture.hasPixels {
            paint(picture, in: band)
        } else {
            canvas.fill(CGRect(x: band.minX + 3, y: band.maxY - 2, width: band.width - 6, height: 1), argb: font.color & 0x00FF_FFFF | 0x8000_0000)
        }
        let middle = band.midY
        if let expand {
            let size = expand.frameSize
            paint(expand, in: CGRect(x: band.minX + 3, y: (middle - size.height / 2).rounded(), width: size.width, height: size.height),
                  frame: min(1, expand.frameCount - 1))
        }
        if let switches {
            let size = switches.frameSize
            paint(switches, in: CGRect(x: switchX, y: (middle - size.height / 2).rounded(), width: size.width, height: size.height))
        }
        let members = tracks.filter { $0.group == group }
        let seconds = members.reduce(0) { $0 + $1.seconds }
        let length = seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
        let totals = "\(members.count) / \(length)"
        let totalsWidth = AIMPSkinText.width(totals, font: font)
        canvas.draw(totals, font: font, at: CGPoint(x: band.maxX - totalsWidth - 8, y: middle), centeredIn: nil, clippedTo: band)
        canvas.draw(group, font: font, at: CGPoint(x: textX, y: middle), centeredIn: nil,
                    clippedTo: CGRect(x: textX, y: band.minY, width: max(0, band.maxX - totalsWidth - 16 - textX), height: band.height))
    }
}
