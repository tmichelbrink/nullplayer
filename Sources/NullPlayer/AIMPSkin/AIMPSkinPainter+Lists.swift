import CoreGraphics
import CoreText
import Foundation

extension AIMPSkinPainter {
    /// NullPlayer's playlist in the skin's colours and fonts, as AIMP lays its list out: a header over
    /// each group (its expand button, switch, name, and its run's count and length, `headers`), then
    /// each track on two lines, its switch, number, title and length, its format and size under the
    /// title with its rating marks at the right; the playing row and the selected one lit. AIMP 2's
    /// list (`classic`) is one line a track. `shown` are the rows the quick search leaves, `rows`
    /// those in view (`AIMPSkinLayout.Look.playlist`).
    func drawPlaylist(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int],
                      headers: [Int: AIMPSkinLayout.GroupHeader], in rect: CGRect) {
        // Its own background picture (GX-77's paper sheet), else its background colour.
        if let picture = image(style.picture), picture.hasPixels {
            paint(picture, in: rect)
        } else {
            canvas.fill(rect, argb: argb(style.background))
        }
        context.saveGState()
        context.clip(to: rect)
        if style.classic {
            drawClassicRows(style, rows: rows, shown: shown, in: rect)
        } else {
            drawGroupedRows(style, rows: rows, shown: shown, headers: headers, in: rect)
        }
        context.restoreGState()
    }

    /// A row's track, its line's rect under any header, and its state; its picture and fill painted
    /// over `lit` (the whole line unless given).
    private func beginRow(_ slot: AIMPSkinLayout.Rows.Slot, style: AIMPSkinControl.Playlist, shown: [Int], in rect: CGRect,
                          lit: (CGRect) -> CGRect = { $0 }) -> (index: Int, row: AIMPSkinPlayerSnapshot.Playlist.Row, line: CGRect,
                                                                  state: AIMPSkinControl.Playlist.Row) {
        let index = shown[slot.row], row = host.player.playlist.rows[index]
        let line = CGRect(x: rect.minX, y: rect.minY + slot.top + slot.header, width: rect.width, height: slot.height - slot.header)
        let playing = index == host.player.playlistIndex, selected = flow.state.lists.playlistSelection.contains(index)
        let state: AIMPSkinControl.Playlist.Row = playing && selected ? .playingSelected : playing ? .playing : selected ? .selected : .normal
        if let rowPicture = image(style.rowPicture), rowPicture.hasPixels { paint(rowPicture, in: line) }
        canvas.fill(lit(line), argb: argb(style.fills[state]))
        return (index, row, line, state)
    }

    private static func time(_ seconds: Int) -> String {
        seconds > 0 ? AIMPSkinFormat.minutes(seconds) : ""
    }

    private static func timeWidth(_ time: String, font: AIMPSkinFont) -> CGFloat {
        CGFloat(time.count) * CGFloat(font.height) * 0.55 + 6
    }

    /// AIMP 2's rows: the number and title, the length at the right, on one line.
    private func drawClassicRows(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int], in rect: CGRect) {
        for slot in rows.slots {
            let (index, row, line, state) = beginRow(slot, style: style, shown: shown, in: rect)
            guard let font = style.fonts[state].map({ self.font($0) }) else { continue }
            let time = Self.time(row.seconds), timeWidth = Self.timeWidth(time, font: font)
            canvas.draw(time, font: font, at: CGPoint(x: line.maxX - timeWidth, y: line.midY), centeredIn: nil, clippedTo: line)
            canvas.draw("\(index + 1). \(row.title)", font: font, at: CGPoint(x: line.minX + 3, y: line.midY), centeredIn: nil,
                        clippedTo: CGRect(x: line.minX, y: line.minY, width: max(0, line.width - timeWidth - 4), height: line.height))
        }
    }

    /// AIMP's rows: group headers, and two lines a track.
    private func drawGroupedRows(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int],
                                 headers: [Int: AIMPSkinLayout.GroupHeader], in rect: CGRect) {
        let drawn = { (name: String?) in self.image(name).flatMap { $0.hasPixels ? $0 : nil } }
        let expand = drawn(style.expandButtons), switches = drawn(style.switches)
        let headerSwitches = drawn(style.headerSwitches) ?? switches, marks = drawn(style.marks)
        // The switches stand in a column after the expand buttons'; the text after them.
        let switchX = rect.minX + 3 + (expand.map { $0.frameSize.width + 3 } ?? 0)
        let textX = switchX + (switches.map { $0.frameSize.width + 4 } ?? 0)
        for slot in rows.slots {
            if slot.header > 0, let header = headers[slot.row] {
                drawGroupHeader(header, style: style, expand: expand, switches: headerSwitches, switchX: switchX, textX: textX,
                                in: CGRect(x: rect.minX, y: rect.minY + slot.top, width: rect.width, height: slot.header))
            }
            let (index, row, line, state) = beginRow(slot, style: style, shown: shown, in: rect) { line in
                CGRect(x: textX - 2, y: line.minY, width: max(0, line.maxX - textX + 2), height: line.height)
            }
            guard let font = style.fonts[state].map({ self.font($0) }) else { continue }
            let detail = style.detailFonts[state].map { self.font($0) } ?? font
            let first = AIMPSkinPlaylistMetrics.titleMiddle(top: line.minY, line: CGFloat(font.height))
            let second = AIMPSkinPlaylistMetrics.detailsMiddle(top: line.minY, line: CGFloat(font.height), detail: CGFloat(detail.height))
            if let switches {
                let size = switches.frameSize
                paint(switches, in: CGRect(x: switchX, y: (first - size.height / 2).rounded(), width: size.width, height: size.height))
            }
            // The number, the title after it, and the details under the title.
            let number = "\(index + 1). "
            let titleX = textX + canvas.width(number, font: font)
            let time = Self.time(row.seconds), timeWidth = Self.timeWidth(time, font: font)
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
    }

    /// A group's header: its picture (else a rule under it in the header's colour), its expand
    /// button shown open, its switch, its name, and at the right its run's count and length
    /// (`24 / 1:35:02`).
    private func drawGroupHeader(_ header: AIMPSkinLayout.GroupHeader, style: AIMPSkinControl.Playlist,
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
        let totals = "\(header.count) / \(AIMPSkinFormat.length(header.seconds))"
        let totalsWidth = canvas.width(totals, font: font)
        canvas.draw(totals, font: font, at: CGPoint(x: band.maxX - totalsWidth - 8, y: middle), centeredIn: nil, clippedTo: band)
        canvas.draw(header.name, font: font, at: CGPoint(x: textX, y: middle), centeredIn: nil,
                    clippedTo: CGRect(x: textX, y: band.minY, width: max(0, band.maxX - totalsWidth - 16 - textX), height: band.height))
    }
}
