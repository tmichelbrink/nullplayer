import CoreGraphics
import Foundation

extension AIMPSkinAIMP3 {
    /// Reads the `Shaped` form into the model: the names links resolve against, then every item
    /// and control, numbered as an AIMP 4 form's are (an item's items, then its own controls).
    struct Build {
        let shape: Shape
        let dialect: AIMPSkinDialect
        /// The `.lng` strings the captions read (`@Lng:N;`).
        var strings: [String: String] = [:]

        /// `companions`: the windows beside the main form, each with its own form (AIMP 2's equalizer).
        func index(_ form: (root: Shaped, sizingEdge: String?), companions: [(companion: AIMPSkin.Companion, root: Shaped)] = [])
            -> AIMPSkinIndex {
            var names = AIMPSkinIndex.Names()
            var hidden = Set<String>()
            // The windows' names first, as an AIMP 4 index reads them: their keys show and hide them.
            for (companion, _) in companions {
                names.items.insert(companion.name)
                if !companion.initiallyVisible { hidden.insert(companion.name) }
            }
            func gather(_ item: Shaped) {
                // Its saved visibility is the first item's of the name, the one lookups find.
                if names.items.insert(item.name).inserted, !item.layout.savedShown { hidden.insert(item.name) }
                for spec in item.controls {
                    for expression in spec.links.compactMap(\.expression) where names.expressions[expression] == nil {
                        names.expressions[expression] = AIMPSkinExpression(expression)
                    }
                }
                item.items.forEach(gather)
            }
            gather(form.root)
            companions.forEach { gather($0.root) }
            var sizing: [String: AIMPSkinIndex.Sizing] = [:]
            if let edge = form.sizingEdge.flatMap(Double.init), edge > 0 { sizing[""] = .init(edge: CGFloat(edge), initialSize: nil) }
            var index = AIMPSkinIndex(names: names, companions: companions.map(\.companion), sizing: sizing, strings: strings,
                                      dialect: dialect, hidden: hidden)
            var made = Made(index: index)
            func window(_ root: Shaped) -> AIMPSkinItem {
                AIMPSkinItem(name: nil, className: nil, isItem: false, layout: Shape.layout(dock: nil),
                             bindings: AIMPSkinBindings(links: [], declared: false), items: [made.item(root)])
            }
            let main = window(form.root)
            let windows = companions.map { (name: $0.companion.name, form: window($0.root)) }
            index.hold(main: main, companions: windows, holders: [:])
            return index
        }
    }

    /// Items and controls read against `index`, each control numbered in turn.
    private struct Made {
        let index: AIMPSkinIndex
        var controls = 0

        mutating func item(_ shaped: Shaped) -> AIMPSkinItem {
            let items = shaped.items.map { item($0) }
            let controls = shaped.controls.map { control($0) }
            return AIMPSkinItem(name: shaped.name, className: "LayoutContainer", layout: shaped.layout,
                                bindings: AIMPSkinBindings(links: [], declared: false), texture: shaped.texture,
                                items: items, controls: controls)
        }

        mutating func control(_ spec: Spec) -> AIMPSkinControl {
            let id = AIMPSkinControl.ID(value: controls)
            controls += 1
            let names = index.names
            let bindings = AIMPSkinBindings(links: spec.links.map {
                AIMPSkinLink(source: $0.source, pin: $0.pin, target: $0.target, expression: $0.expression, names: names)
            }, declared: !spec.links.isEmpty)
            return AIMPSkinControl(id: id, name: spec.name, className: spec.type.rawValue, styleKey: spec.name,
                                   kind: kind(spec, bindings: bindings), bindings: bindings, placement: spec.placement,
                                   picture: spec.picture, flipY: spec.flipped, text: text(spec, bindings: bindings),
                                   input: AIMPSkinControl.Input(className: spec.type.rawValue, handlers: .init(popupMenu: spec.popupMenu),
                                                                bindings: bindings, index: index),
                                   writtenMargins: spec.placement.margins.map(Double.init), confined: spec.confined)
        }

        private func kind(_ spec: Spec, bindings: AIMPSkinBindings) -> AIMPControlClass {
            func key(_ role: AIMPControlClass.Key.Role) -> AIMPControlClass {
                .key(.init(role: role, fill: nil, fixedFrame: spec.frame ?? 0, framesPerState: spec.framesPerState))
            }
            func slider(seek: Bool) -> AIMPControlClass {
                .slider(.init(isSeek: seek, isVertical: spec.type == .sliderVertical, thumb: spec.thumb, progressColor: nil, color: nil))
            }
            // Held as an AIMP 4 form's are (`AIMPControlClass`).
            let digits = AIMPControlClass.Digits(places: spec.digits.flatMap { Int($0) },
                                                 indent: min(max(spec.indent.flatMap { Int($0) } ?? 0, -4_096), 4_096))
            if spec.isPlaylist { return .playlist(playlist(spec.playlist ?? [:])) }
            switch spec.type {
            case .button: return key(.button)
            case .toggle: return key(.switch)
            case .textDisplay: return key(.textDisplay)
            case .runningLine: return key(.runningLine)
            case .timeDisplay: return .time(digits)
            case .digitsDisplay: return .digits(digits)
            case .seekBar: return slider(seek: true)
            case .slider, .sliderVertical: return slider(seek: false)
            case .sliderMasked: return .selector
            case .animator: return .animator(.init(interval: spec.interval.flatMap { Double($0) }, reversed: false))
            case .spectrum:
                return .spectrum(.init(columns: min(max(1, spec.columns.flatMap { Int($0) } ?? 16), 4_096),
                                       indent: CGFloat(min(max(0, spec.columnsIndent.flatMap { Int($0) } ?? 1), 4_096)),
                                       color: spec.color.map(AIMPSkinColor.argb), peakColumns: spec.peakColumns, peakSegment: 1))
            case .coverArt: return .coverArt(.init(coverFrame: nil, blur: nil))
            case .visualDisplay:
                return .visualization(.init(columns: 16, indent: 1, color: nil, peakColumns: nil, peakSegment: 1), cover: nil)
            case .equalizer: return .equalizer(preamp: AIMPSkinColor.visible(argb: spec.preamp), curve: AIMPSkinColor.visible(argb: spec.curve))
            case .scrollBar: return .playlistScrollBar(thumb: spec.thumb)
            case .panel: return key(.picture)
            }
        }

        /// What it shows, as an AIMP 4 control's `Caption`, `Template`, `Font` and `Alignment` read.
        private func text(_ spec: Spec, bindings: AIMPSkinBindings) -> AIMPSkinControl.Text {
            var font = AIMPSkinFont(flat: spec.font) ?? .standard
            if font.name.isEmpty { font.name = AIMPSkinFont.standard.name }
            let alignment = AIMPSkinTextAlign(spec.alignment)
            return AIMPSkinControl.Text(font: font,
                                        display: .resolve(caption: spec.caption, template: spec.template, bindings: bindings, index: index),
                                        running: AIMPSkinControl.Text.running(template: spec.template, bindings: bindings, index: index),
                                        alignment: alignment, declaresAlignment: spec.alignment != nil, isLeftJustified: alignment == .left,
                                        wraps: false, sizesHeight: false, declaresAutoSize: false)
        }

        /// The playlist's flat `Resources` (`Shape.playlistControls`): fonts as `name,BGR,height,style`,
        /// colours Delphi numbers.
        private func playlist(_ resources: [String: String]) -> AIMPSkinControl.Playlist {
            typealias Row = AIMPSkinControl.Playlist.Row
            func color(_ key: String) -> AIMPSkinColor? { resources[key].flatMap { Int64($0) }.map { .argb(AIMPSkinColor.argb(delphi: $0)) } }
            let fonts = AIMPSkinControl.Playlist.fonts { state, line in
                AIMPSkinFont(flat: resources[line + "Font" + (state == "Normal" ? "" : state)])
            }
            // A background that is no number names a colour resource, as an AIMP 4 list's would.
            let background = color("BackgroundColor") ?? resources["BackgroundColor"].flatMap { $0.isEmpty ? nil : .resource($0) }
            var fills: [Row: AIMPSkinColor] = [:]
            fills[.playingSelected] = color("ItemHighlightColorSelectedPlaying")
            fills[.playing] = color("ItemHighlightColorPlaying")
            fills[.selected] = color("ItemHighlightColorSelected")
            var playlist = AIMPSkinControl.Playlist(
                picture: resources["Skin"], background: background, rowPicture: nil,
                fonts: fonts.rows, fills: fills, detailFonts: fonts.details, headerFont: fonts.header, headerPicture: nil,
                expandButtons: resources["HeaderExpandButtons"], marks: resources["ItemMarks"],
                switches: resources["ItemSwitches"], headerSwitches: resources["ItemSwitches"])
            playlist.classic = index.dialect.classicPlaylist
            return playlist
        }
    }
}
