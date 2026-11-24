import CoreGraphics
import Foundation

extension AIMPSkinLegacy {
    /// Builds the form tree the later formats have from an AIMP 3.0 attribute-style item tree and
    /// the `Object`s and `Settings` a reader found in `main.ini`.
    struct Translator {
        let documents: AIMPSkinDocuments
        let images: [String: AIMPSkinImage]
        let settings: Settings
        /// A window of the skin's own that the equalizer keys show and hide (AIMP 2's); nil when
        /// they open the equalizer as AIMP's action does.
        let equalizerWindow: String?
        /// Each item's objects, back to front, by the item's name.
        let objects: [String: [Object]]
        var unnamed = 0
        /// The dock sites' frame documents being read into the tree (lowercased), and how many have
        /// been: a frame that docks itself, or frames that dock each other, would recurse until the
        /// stack ran out, and frames each docking two others would double at every level.
        private var framesReading: Set<String> = []
        private var framesRead = 0
        /// More frames than any AIMP 3.0 skin docks (`PlaylistFrame` and `EqFrame`).
        private static let mostFrames = 64

        init(documents: AIMPSkinDocuments, images: [String: AIMPSkinImage], objects: [Object], settings: Settings,
             equalizerWindow: String? = nil) {
            self.documents = documents
            self.images = images
            self.settings = settings
            self.equalizerWindow = equalizerWindow
            // By item name without regard to case, as `[Parents]` and the layout may differ in it.
            self.objects = Dictionary(grouping: objects, by: { $0.item.lowercased() }).mapValues { $0.sorted { $0.z < $1.z } }
        }

        /// A picture that draws: AIMP 3.0 keeps a 0×0 one for every object.
        func picture(_ name: String) -> AIMPSkinImage? {
            images[(name + ".img").lowercased()].flatMap { $0.hasPixels ? $0 : nil }
        }

        mutating func form(_ layout: AIMPNode) -> AIMPNode {
            var items: [AIMPNode] = []
            for child in layout.children("item") { items.append(item(child)) }
            // The `<layout>`'s own `MinSize`/`MaxSize` are left out: AIMP 5.40 opens Cute below its
            // 830x550 and 4CarPC over its 800x480, at what their items take.
            let root = AIMPNode.element("item", ["class": "LayoutContainer", "name": "AIMP3Form"], [
                AIMPNode.propertyList([AIMPNode.property("Alignment", "laClient")]),
                AIMPNode.element("items", [:], items),
            ])
            var size = naturalSize(root)
            if let least = settings.minimumSize {
                size = CGSize(width: max(size.width, least.width), height: max(size.height, least.height))
            }
            var props = [AIMPNode.property("Alignment", "laClient"), AIMPNode.property("SizeMinimal", "\(Int(size.width)),\(Int(size.height))")]
            // The window sizes from its edges (`[MainFrame]`); the size above is its smallest.
            if let edge = settings.sizingEdge { props.append(AIMPNode.property("SizingHitTestAreaWidth", edge)) }
            return AIMPNode.element("layout", [:], [AIMPNode.element("items", [:], [
                AIMPNode.element("item", root.attributes, [
                    AIMPNode.propertyList(props),
                    AIMPNode.element("items", [:], items),
                ]),
            ])])
        }

        /// One layout item, its children docked lowest `AlignLevel` first, and the controls
        /// `[Parents]` puts in it.
        mutating func item(_ source: AIMPNode) -> AIMPNode {
            let name: String
            if let given = source["Name"] {
                name = given
            } else {
                unnamed += 1
                name = "AIMP3Item\(unnamed)"
            }
            let align = ["top": "laTop", "bottom": "laBottom", "left": "laLeft", "right": "laRight", "client": "laClient"][
                source["Align"] ?? "top"] ?? "laTop"
            var props = [AIMPNode.property("Alignment", align)]
            // Its level among its docked siblings, as AIMP's conversion writes it: the layout orders by
            // it, also where a form's or frame's own items come in another order.
            if let level = source["AlignLevel"], Int(level) != nil { props.append(AIMPNode.property("AlignmentLevel", level)) }
            // The playlist frame's top dock is its caption while it floats: AIMP 5.40 shows it only
            // undocked (its conversion binds it `not PlaylistFrame.Docked`), and NullPlayer docks the
            // frame. NGuvu's 42-px caption over its 295-px bars, Bloom's 33-px one.
            if name.caseInsensitiveCompare("PlsTopDock") == .orderedSame, framesReading.contains("playlistframe.xml") {
                props.append(AIMPNode.property("Visible", "False"))
            }
            if let margins = source["AlignMargins"] { props.append(AIMPNode.property("AlignmentMargins", margins)) }
            if picture(name) != nil { props.append(AIMPNode.property("Texture", name)) }
            var items: [AIMPNode] = []
            for child in source.children("item").enumerated()
                .sorted(by: { (Int($0.element["AlignLevel"] ?? "") ?? 0, $0.offset) < (Int($1.element["AlignLevel"] ?? "") ?? 0, $1.offset) }) {
                items.append(item(child.element))
            }
            var controls: [AIMPNode] = []
            // A dock site's own minimum, which wins over the item's limits and its content's size.
            var siteMinimum: String?
            if source["Class"] == "TAIMPLayoutDockSiteItem" {
                // A dock site holds a frame of its own layout (`PlaylistFrame`; the equalizer's is
                // `EqFrame`); one that does not read is a finding, and the site is left as if it had none.
                let file = name == "EqualizerFrame" ? "EqFrame.xml" : name + ".xml"
                if !framesReading.contains(file.lowercased()), framesRead < Self.mostFrames, let layout = documents.node(file) {
                    framesRead += 1
                    framesReading.insert(file.lowercased())
                    items = []
                    for child in layout.children("item") { items.append(item(child)) }
                    framesReading.remove(file.lowercased())
                } else if name == "TabCtrl" {
                    controls += tabs()
                    // With no bar of its own, the row is as tall as its tab (AIMP 2's Old Systems).
                    if picture(name) == nil, let tab = picture("TabCtrlTab") {
                        siteMinimum = "0,\(Int(tab.frameSize.height))"
                    }
                } else if name == "Container" {
                    controls += playlist()
                    // An AIMP 3.0 skin's playlist takes no room of its own: AIMP 5.40 opens it at what its
                    // other parts take (Bloom's list, 0 px under its tab row; Pure White's and BYG's).
                    if settings.playlistRoom { siteMinimum = "0,170" }
                }
            }
            // The item's own limits and resize flags, as AIMP 5.40's conversion writes them (Experience's
            // 176x301 cover panel, bars the user cannot size); a site's minimum above wins.
            let limits = Self.limits(source)
            props += limits.filter { $0["name"] != "SizeMinimal" }
            var minimum = siteMinimum.map { AIMPNode.property("SizeMinimal", $0) } ?? limits.first { $0["name"] == "SizeMinimal" }
            // An item with no picture is as big as what docks in it, and no smaller than its
            // `MinSize`; the renderer is told so.
            let content = contentSize(AIMPNode.element("item", [:], [AIMPNode.propertyList(props + [minimum].compactMap { $0 }),
                                                                     AIMPNode.element("items", [:], items)]))
            if picture(name) == nil, siteMinimum == nil, content.width > 0 || content.height > 0 {
                minimum = AIMPNode.property("SizeMinimal", "\(Int(content.width)),\(Int(content.height))")
            }
            if let minimum { props.append(minimum) }
            controls += self.controls(in: name, size: content)
            return AIMPNode.element("item", ["class": "LayoutContainer", "name": name], [
                AIMPNode.propertyList(props), AIMPNode.element("items", [:], items), AIMPNode.element("controls", [:], controls),
            ])
        }

        /// An AIMP 3.0 item's `MinSize`, `MaxSize`, `AllowResizeByWidth`/`Height` and `AutoSize`, as the
        /// properties AIMP 4 names them.
        static func limits(_ source: AIMPNode) -> [AIMPNode] {
            var found: [AIMPNode] = []
            if let value = source["MinSize"] { found.append(AIMPNode.property("SizeMinimal", value)) }
            if let value = source["MaxSize"] { found.append(AIMPNode.property("SizeMaximal", value)) }
            for key in ["AllowResizeByWidth", "AllowResizeByHeight", "AutoSize"] {
                if let value = source[key] { found.append(AIMPNode.property(key, value == "0" ? "False" : "True")) }
            }
            return found
        }

        /// The playlist tabs: NullPlayer has one playlist, its tab lit.
        func tabs() -> [AIMPNode] {
            guard let tab = picture("TabCtrlTab") else { return [] }
            let size = tab.frameSize
            return [AIMPNode.element("control", ["class": "TextDisplay", "name": "PlaylistTab"], [AIMPNode.propertyList([
                placement(anchors: [1, 1, 0, 0], margins: [0, 0, 0, 0], size: size),
                AIMPNode.property("Skin", "TabCtrlTab"), AIMPNode.property("Frame", tab.frameCount > 2 ? "2" : "0"),
                AIMPNode.property("Caption", AIMPSkinList.playlistName), AIMPNode.property("Font", settings.activeTab ?? "Tahoma,0,12,0"),
            ])])]
        }

        /// Whether a row with the fill `key` names (`ABK`, `SBK`, `SABK`) is dark: its own fill where the
        /// skin gives one, else the list's (Hysteria's playing row, light grey on its dark list, takes
        /// black titles).
        private func rowIsDark(_ key: String?, list: Bool) -> Bool {
            guard let key, let bgr = settings.playlist[key].flatMap({ Int($0) }) else { return list }
            return Self.luminance(red: UInt8(bgr & 0xFF), green: UInt8((bgr >> 8) & 0xFF), blue: UInt8((bgr >> 16) & 0xFF)) < 0.5
        }

        /// Whether the list's background, its `PlaylistWallpaper` or else its `BK` colour, is dark.
        private func listIsDark() -> Bool {
            if let picture = picture("PlaylistWallpaper")?.frame(0) {
                var pixel = [UInt8](repeating: 0, count: 4)
                if let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.interpolationQuality = .medium
                    context.draw(picture, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    return Self.luminance(red: pixel[0], green: pixel[1], blue: pixel[2]) < 0.5
                }
            }
            let bgr = settings.playlist["BK"].flatMap { Int($0) } ?? 0
            return Self.luminance(red: UInt8(bgr & 0xFF), green: UInt8((bgr >> 8) & 0xFF), blue: UInt8((bgr >> 16) & 0xFF)) < 0.5
        }

        private static func luminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
            (0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)) / 255
        }

        /// An AIMP font (`name,colour,height,style`) with a colour of 0, AIMP's automatic one, made
        /// white over a dark list; black stays as it is over a light one.
        static func automaticColour(_ font: String, dark: Bool) -> String {
            var parts = font.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count > 1, Int(parts[1].trimmingCharacters(in: .whitespaces)) == 0, dark else { return font }
            parts[1] = "16777215"
            return parts.joined(separator: ",")
        }

        /// The playlist in `[Playlist]`'s fonts and colours, its scroll bar down the right.
        func playlist() -> [AIMPNode] {
            var resources: [AIMPNode] = []
            // AIMP 3 draws a track on two lines, the title in the `…Hdr` font and the details under it in
            // the plain one; NullPlayer's one line is the title. A title colour of 0 is AIMP's automatic
            // one, light over a dark row and dark over a light one (GREEX's white titles on blue,
            // Aero Style's black on white glass): the row's own fill where it has one.
            let dark = listIsDark()
            let rows: [(resource: String, title: String, details: String, fill: String?)] = [
                ("ItemLine1Font", "NrmHdr", "Nrm", nil), ("ItemLine1FontPlaying", "ActHdr", "Act", "ABK"),
                ("ItemLine1FontSelected", "SelHdr", "Sel", "SBK"),
                ("ItemLine1FontPlayingSelected", "SelActHdr", "SelAct", settings.playlist["SABK"] == nil ? "SBK" : "SABK"),
            ]
            for (resource, title, details, fill) in rows {
                if let font = settings.playlist[title] {
                    resources.append(AIMPNode.property(resource, Self.automaticColour(font, dark: rowIsDark(fill, list: dark))))
                } else if let font = settings.playlist[details] {
                    resources.append(AIMPNode.property(resource, font))
                }
            }
            // The details under it, in the plain fonts; a group's header in `Header`.
            for (resource, key) in [("ItemLine2Font", "Nrm"), ("ItemLine2FontPlaying", "Act"), ("ItemLine2FontSelected", "Sel"),
                                    ("ItemLine2FontPlayingSelected", "SelAct"), ("HeaderFont", "Header")] {
                if let font = settings.playlist[key] { resources.append(AIMPNode.property(resource, font)) }
            }
            for (resource, name) in [("HeaderExpandButtons", "PlaylistExpandButtons"), ("ItemSwitches", "PlaylistSwitches"),
                                     ("ItemMarks", "PlaylistRating")] where picture(name) != nil {
                resources.append(AIMPNode.property(resource, name))
            }
            for (resource, key) in [("BackgroundColor", "BK"), ("ItemHighlightColorPlaying", "ABK"),
                                    ("ItemHighlightColorSelected", "SBK"), ("ItemHighlightColorSelectedPlaying", "SABK")] {
                if let value = settings.playlist[key] { resources.append(AIMPNode.property(resource, value)) }
            }
            let bar = Int(picture("PlaylistScroll")?.frameSize.width ?? 0)
            // `PlaylistWallpaper` is the list's background where the skin has one (GREEX's blue, Aero
            // Style's white glass; 14 of the catalogue's AIMP 3 skins), over `BK`.
            if picture("PlaylistWallpaper") != nil { resources.append(AIMPNode.property("Skin", "PlaylistWallpaper")) }
            var controls = [AIMPNode.element("control", ["class": "Panel", "name": "Playlist", "link": "Playlist"], [AIMPNode.propertyList([
                placement(anchors: [1, 1, 1, 1], margins: [0, 0, bar, 0], size: .zero),
                AIMPNode.element("property", ["name": "Resources"], resources),
            ])])]
            if bar > 0 {
                var props = [placement(anchors: [0, 1, 1, 1], margins: [0, 0, 0, 0], size: CGSize(width: bar, height: 0)),
                             AIMPNode.property("Skin", "PlaylistScroll"),
                             AIMPNode.bindings(AIMPNode.binding("Playlist", "Position", "Action"))]
                if picture("PlaylistScroll_thumb") != nil { props.append(AIMPNode.property("SkinThumb", "PlaylistScroll_thumb")) }
                controls.append(AIMPNode.element("control", ["class": "ScrollBar", "name": "PlaylistScroll"], [AIMPNode.propertyList(props)]))
            }
            return controls
        }

        /// The controls in `item`, back to front, less those parked.
        func controls(in item: String, size: CGSize) -> [AIMPNode] {
            (objects[item.lowercased()] ?? []).flatMap { object -> [AIMPNode] in
                let rect = AIMPPlacement.rect(anchors: object.anchors, margins: object.margins, size: object.size,
                                              in: CGRect(origin: .zero, size: size)) ?? .zero
                // Parked objects sit left of or above the item; those past its right or bottom edge
                // show when the window grows (Vega's EQ, right of the info panel), as does one anchored
                // to both sides that has no room yet at the item's own size.
                let stretches = object.anchors.count == 4 ? (object.anchors[0] != 0 && object.anchors[2] != 0,
                                                             object.anchors[1] != 0 && object.anchors[3] != 0) : (false, false)
                guard rect.width > 0 || stretches.0, rect.height > 0 || stretches.1, rect.maxX > 0 || stretches.0,
                      rect.maxY > 0 || stretches.1 else { return [] }
                return control(object)
            }
        }

        /// The control, or controls, an object is.
        func control(_ object: Object) -> [AIMPNode] {
            let name = object.name
            let place = placement(anchors: object.anchors, margins: object.margins, size: object.size)
            var props = [place]
            var cls = "Button"
            func bind(_ source: String, _ pin: String, _ target: String) {
                props.append(AIMPNode.bindings(AIMPNode.binding(source, pin, target)))
            }
            func font() { if let font = object.font { props.append(AIMPNode.property("Font", font)) } }
            func align() {
                if let align = [1: "taRightJustify", 2: "taCenter"][object.textAlign ?? 0] { props.append(AIMPNode.property("Alignment", align)) }
            }
            let thumb = picture(name + "_thumb") != nil
            if picture(name) != nil { props.append(AIMPNode.property("Skin", name)) }
            switch object.kind {
            case .text(let template):
                cls = "TextDisplay"
                if template.contains("%") {
                    props.append(AIMPNode.property("Template", template))
                    bind("prvPlayingFileInfo", "FileInfo", "DisplayValue")
                } else {
                    props.append(AIMPNode.property("Caption", template))
                }
                font()
                align()
            case .time(let time, let digits, let indent):
                cls = "TimeDisplay"
                props += [AIMPNode.property("Digits", digits), AIMPNode.property("IndentBetweenDigits", indent)]
                let pin: String? = switch time {
                case .duration: "TrackDuration"
                case .remaining: "TrackPositionRemaining"
                case .position: "TrackPosition"
                case .sleepTimer: nil
                }
                if let pin {
                    bind("prvPlayerState", pin, "DisplayValue")
                } else {
                    // The sleep timer reads zero: its value pinned by an expression.
                    props.append(AIMPNode.bindings(AIMPNode.element("link", ["Source": "prvPlayerState", "SourcePin": "TrackPosition",
                                                                              "TargetPin": "DisplayValue", "Expression": "0"])))
                }
            case .bitrate:
                cls = "DigitsDisplay"
                bind("prvPlayingFileInfo", "Bitrate", "DisplayValue")
            case .sampleRate:
                cls = "DigitsDisplay"
                bind("prvPlayingFileInfo", "SampleRate", "DisplayValue")
            case .status(let showsState):
                // A picture per state: stopped, playing, paused.
                cls = "DigitsDisplay"
                props.append(AIMPNode.property("Digits", "1"))
                if showsState { bind("prvPlayerState", "State", "DisplayValue") }
            case .seekBar:
                cls = "SeekBar"
                if thumb { props.append(AIMPNode.property("SkinThumb", name + "_thumb")) }
            case .animator(let interval):
                // AIMP 3 runs them all the time (Vega's logo turns while stopped; a lamp over it hides
                // it while playing).
                cls = "Animator"
                props += [AIMPNode.property("AnimationInterval", interval),
                          AIMPNode.bindings(AIMPNode.binding("AIMPMainForm", "Visible", "Accessibility"))]
            case .spectrum(let peaks, let indent, let colour, let flipped, let masked):
                var spectrum = [place, AIMPNode.property("ColumnsCount", peaks), AIMPNode.property("ColumnsIndent", indent)]
                // With `SkinHitTestMask` 1 the picture is the bars, lit up to each one's level and see-through
                // elsewhere (GREEX's fifty spectra a pixel apart, black bars smeared into one shape over
                // its blue display; Aero Style's dark bars on glass): no backdrop, no `Color`.
                if masked, picture(name) != nil {
                    spectrum.append(AIMPNode.property("PeakColumns", name))
                    if flipped { spectrum.append(AIMPNode.property("FlipVertically", "True")) }
                    return [AIMPNode.element("control", ["class": "SpectrumDisplay", "name": name], [AIMPNode.propertyList(spectrum)])]
                }
                // Its picture is the empty display; the bars are `Color` (a Delphi colour), `Peaks` of them.
                if let colour { spectrum.append(AIMPNode.property("Color", String(AIMPSkinColor.argb(delphi: colour)))) }
                if flipped { spectrum.append(AIMPNode.property("FlipVertically", "True")) }
                return [AIMPNode.element("control", ["class": "TextDisplay", "name": name + "Back"], [AIMPNode.propertyList(props)]),
                        AIMPNode.element("control", ["class": "SpectrumDisplay", "name": name], [AIMPNode.propertyList(spectrum)])]
            case .coverArt:
                // Its picture with no cover, the cover over it.
                return [AIMPNode.element("control", ["class": "TextDisplay", "name": name + "Back"], [AIMPNode.propertyList(props)]),
                        AIMPNode.element("control", ["class": "CoverArtDisplay", "name": name], [AIMPNode.propertyList([place])])]
            case .equalizerDisplay(let curve, let preamp):
                // Its picture is the grid; the curve is `EQVISE`, the preamp line `EQVISL`.
                cls = "EqualizerDisplay"
                for (key, colour) in [("ColorCurve", curve), ("ColorPreamp", preamp)] {
                    if let colour {
                        props.append(AIMPNode.element("property", ["name": key], [AIMPNode.property("Value", String(AIMPSkinColor.argb(delphi: colour)))]))
                    }
                }
            case .object(let key) where key == "multidisplay":
                // AIMP 2's visualization screen: its picture (Hameleon's logo) shows when none runs,
                // the visualization over it otherwise; VisPrev and VisNext step it.
                return [AIMPNode.element("control", ["class": "TextDisplay", "name": name + "Back"], [AIMPNode.propertyList(props)]),
                        AIMPNode.element("control", ["class": "VisualDisplay", "name": name], [AIMPNode.propertyList([place])])]
            case .object(let key):
                guard let made = aimpObject(key, name: name, thumb: thumb, orientation: object.orientation, into: &props) else { return [] }
                cls = made
                if key == "infobar" || key == "countlabel" || key == "lengthlabel" { font() }
                if key == "countlabel" || key == "lengthlabel" { align() }
            }
            return [AIMPNode.element("control", ["class": cls, "name": name], [AIMPNode.propertyList(props)])]
        }

        /// The control class of AIMP's own object `key`, its bindings added to `props`; nil for an
        /// object NullPlayer has no counterpart for and that draws nothing.
        private func aimpObject(_ key: String, name: String, thumb: Bool, orientation: Int?, into props: inout [AIMPNode]) -> String? {
            func bind(_ source: String, _ pin: String, _ target: String) {
                props.append(AIMPNode.bindings(AIMPNode.binding(source, pin, target)))
            }
            if let window = equalizerWindow, key == "eqbtn" || key == "hidebtn" {
                // AIMP 2's equalizer is a window beside the player: its key and the window's own
                // hide key show and hide it.
                bind(window, "Visible", "Action")
            } else if let action = Self.actions[key] {
                bind(action, "Action", "Action")
            } else if key == "playpausebtn" {
                // Play's four frames, then pause's, shown while playing.
                props += [AIMPNode.property("FramesPerState", "4"),
                          AIMPNode.bindings(AIMPNode.binding("acPlayerPlayPause", "Action", "Action"),
                                            AIMPNode.binding("prvPlayerState", "State", "State"))]
            } else if let action = Self.switches[key] {
                props.append(AIMPNode.property("FramesPerState", "3"))
                bind(action, "Action", "Action")
                return "Switch"
            } else if let menu = Self.menus[key] {
                props.append(AIMPNode.property("PopupMenu", menu))
            } else if let provider = Self.sliders[key] ?? (key == "preamp" || key.hasPrefix("aimpslider") ? "prvEqualizer" : nil) {
                // `Orientation` 0 upright, 1 across, 2 a knob turned through its frames.
                let cls = orientation == 2 ? "SliderMasked" : orientation == 1 ? "Slider" : "SliderVertical"
                if thumb, cls != "SliderMasked" { props.append(AIMPNode.property("SkinThumb", name + "_thumb")) }
                let pin = key == "preamp" ? "Preamp" : key.hasPrefix("aimpslider") ? "Band" + key.dropFirst(10) : "Action"
                bind(provider, pin, "Action")
                return cls
            } else if let provider = Self.effects[key] {
                // AIMP 2's sound effects (Hameleon's CHORUS, ECHO…), under the providers AIMP 3 and
                // later name them: NullPlayer has none, so they rest at off (`AIMPSkinHostState`).
                if thumb { props.append(AIMPNode.property("SkinThumb", name + "_thumb")) }
                bind(provider, "Action", "Action")
                return orientation == 0 ? "SliderVertical" : "Slider"
            } else if key == "infobar" {
                return "RunningLine"
            } else if key == "countlabel" || key == "lengthlabel" {
                bind("Playlist", key == "countlabel" ? "Count" : "Duration", "DisplayValue")
                if key == "lengthlabel" { props.append(AIMPNode.property("Template", "%time(HMS;:;)")) }
                return "TextDisplay"
            } else if picture(name) == nil {
                return nil
            }
            return "Button"
        }

        private static let actions = [
            "playbtn": "acPlayerPlay", "pausebtn": "acPlayerPause", "stopbtn": "acPlayerStop",
            "prevbtn": "acPlayerPrevTrack", "nextbtn": "acPlayerNextTrack", "openbtn": "acPlayerOpenFiles",
            "closebtn": "acMainExit", "totraybtn": "acMainMinimize", "fileinfo": "acPlayableFileShowFileInfoAtCursor",
            "tageditbtn": "acSendToTagEditor", "tagedit": "acSendToTagEditor", "eqbtn": "acEqualizerShow",
            "plsbtn": "acPlaylistShow", "lib": "acMainShowMusicLibrary", "visualbtn": "acVisualizationShow",
            "dspbtn": "acMainDSPManager", "capradio": "acPlayerRadioCapture",
            "visprev": "acVisualPrev", "visnext": "acVisualNext",
            "qficopyfile": "acPlayableFileCopyFileToClipboard", "qficopyfileinfo": "acPlayableFileCopyInfoToClipboard",
        ]
        private static let switches = ["shuffle": "acPlayerShuffle", "repeat_": "acPlayerRepeat", "stayontop": "acMainStayOnTop",
                                       "mutebtn": "acPlayerVolumeMute", "eqswitch": "acEqualizerSwitch"]
        private static let sliders = ["volumebar": "prvVolume", "balanceslider": "prvBalance", "speedslider": "prvSpeed",
                                      "temposlider": "prvTempo", "pitchslider": "prvPitch"]
        /// AIMP 2's sound-effect sliders, which have no NullPlayer counterpart.
        private static let effects = ["chorus": "prvChorus", "flanger": "prvFlanger", "echo": "prvEcho", "reverb": "prvReverb"]
        private static let menus = ["menubtn": "pmMenu", "addbtn": "pmAdd", "delbtn": "pmDelete", "sortbtn": "pmSort",
                                    "miscbtn": "pmMisc", "plsopt": "pmPlaylist", "btnplaylistslistmenu": "pmPlaylists"]

        /// What an item takes up when nothing stretches it, its `AlignmentMargins` around it.
        func naturalSize(_ item: AIMPNode) -> CGSize { AIMPSkinItem.Layout(item).slot(contentSize(item)) }

        /// An item's own size: its picture, else its children docked around each other, its
        /// clients over one another.
        func contentSize(_ item: AIMPNode) -> CGSize {
            var size = item.properties["Texture"]?["value"].flatMap { picture($0)?.frameSize } ?? .zero
            if size == .zero {
                // A hidden item takes no room (the playlist frame's docked-away caption).
                let shown = (item.child("items")?.children("item") ?? []).filter { $0.properties["Visible"]?["value"] != "False" }
                size = AIMPSkinAlignment.aggregate(shown.map { (AIMPSkinItem.Layout($0).dock, naturalSize($0)) }, clients: .overlap)
            }
            return AIMPSkinItem.Layout(item).floored(size)
        }

        func placement(anchors: [Int], margins: [Int], size: CGSize) -> AIMPNode {
            AIMPNode.element("property", ["name": "PlaceInfo", "anchors": anchors.map(String.init).joined(separator: ","),
                                          "margins": margins.map(String.init).joined(separator: ","),
                                          "Size": "\(Int(size.width)),\(Int(size.height))"], [])
        }
    }
}
