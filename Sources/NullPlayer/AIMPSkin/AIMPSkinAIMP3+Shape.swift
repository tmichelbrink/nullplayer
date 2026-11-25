import CoreGraphics
import Foundation

extension AIMPSkinAIMP3 {
    /// One item of the form as the layout documents give it: its docking, picture and natural
    /// size, the items in it, and what each control in it is (`Spec`), not yet read into the model.
    struct Shaped {
        let name: String
        let layout: AIMPSkinItem.Layout
        let texture: String?
        let items: [Shaped]
        let controls: [Spec]
        /// What it takes up when nothing stretches it, its margins around it.
        let natural: CGSize
    }

    /// A control, as an AIMP 4 form would declare it: its class, placement, picture and what its
    /// class reads (`Build.control`).
    struct Spec {
        enum Class: String {
            case button = "Button", toggle = "Switch", textDisplay = "TextDisplay", timeDisplay = "TimeDisplay"
            case digitsDisplay = "DigitsDisplay", seekBar = "SeekBar", animator = "Animator"
            case spectrum = "SpectrumDisplay", coverArt = "CoverArtDisplay", equalizer = "EqualizerDisplay"
            case visualDisplay = "VisualDisplay"
            case slider = "Slider", sliderVertical = "SliderVertical", sliderMasked = "SliderMasked"
            case runningLine = "RunningLine", scrollBar = "ScrollBar", panel = "Panel"
        }

        /// One binding, `source`'s `pin` to `target`.
        struct Link {
            let source: String, pin: String, target: String
            var expression: String? = nil
        }

        var name: String
        var type: Class = .button
        let placement: AIMPPlacement.Info
        var picture: String?
        var links: [Link] = []
        /// `Frame` and `FramesPerState`.
        var frame: Int?
        var framesPerState: Int?
        var caption: String?
        var template: String?
        /// `name,BGR,height,style`.
        var font: String?
        var alignment: String?
        var thumb: String?
        var digits: String?
        var indent: String?
        var interval: String?
        /// A spectrum's bars and their colour (ARGB), its lit picture (`PeakColumns`), upside down.
        var columns: String?
        var columnsIndent: String?
        var color: UInt32?
        var peakColumns: String?
        var flipped = false
        /// An equalizer display's curve and preamp line (ARGB).
        var curve: UInt32?
        var preamp: UInt32?
        var popupMenu: String?
        /// The playlist's `Resources`, flat, as AIMP 4 names them.
        var playlist: [String: String]?
        /// A playlist's `link`.
        var isPlaylist = false

        init(name: String, placement: AIMPPlacement.Info) {
            self.name = name
            self.placement = placement
        }
    }

    /// Reads the layout documents and the objects into `Shaped` items.
    struct Shape {
        let documents: AIMPSkinDocuments
        let images: [String: AIMPSkinImage]
        /// Each item's objects, back to front, by the item's name without regard to case, as
        /// `[Parents]` and the layout may differ in it.
        let objects: [String: [Object]]
        /// `[TabCtrl] ActiveTab`: the lit tab's font.
        let activeTab: String?
        /// `[Playlist]`'s fonts (`Nrm`, `Act`, `Sel`, `SelAct`, their `…Hdr` titles) and colours
        /// (`BK`, `ABK`, `SBK`, `SABK`).
        let playlist: [String: String]
        var unnamed = 0
        /// The dock sites' frame documents being read into the tree (lowercased), and how many have
        /// been: a frame that docks itself, or frames that dock each other, would recurse until the
        /// stack ran out, and frames each docking two others would double at every level.
        private var framesReading: Set<String> = []
        private var framesRead = 0
        /// More frames than any AIMP 3.0 skin docks (`PlaylistFrame` and `EqFrame`).
        private static let mostFrames = 64

        init(documents: AIMPSkinDocuments, images: [String: AIMPSkinImage], objects: [Object], activeTab: String?,
             playlist: [String: String]) {
            self.documents = documents
            self.images = images
            self.objects = Dictionary(grouping: objects, by: { $0.item.lowercased() }).mapValues { $0.sorted { $0.z < $1.z } }
            self.activeTab = activeTab
            self.playlist = playlist
        }

        /// A picture that draws: AIMP 3.0 keeps a 0×0 one for every object.
        func picture(_ name: String) -> AIMPSkinImage? {
            images[(name + ".img").lowercased()].flatMap { $0.hasPixels ? $0 : nil }
        }

        /// The form's one item, `AIMP3Form`, holding the layout's items, no smaller than they take;
        /// `sizingEdge` (`[MainFrame] SizingHitTestAreaWidth`): the window sizes from its edges.
        /// The `<layout>`'s own `MinSize`/`MaxSize` are left out: AIMP 5.40 opens Cute below its
        /// 830x550 and 4CarPC over its 800x480, at what their items take.
        mutating func form(_ layout: AIMPNode, sizingEdge: String?) -> (root: Shaped, sizingEdge: String?) {
            var items: [Shaped] = []
            for child in layout.children("item") { items.append(item(child)) }
            let size = Self.layout(dock: .client).slot(Self.aggregate(items))
            let least = CGSize(width: Int(size.width), height: Int(size.height))
            let root = Shaped(name: "AIMP3Form", layout: Self.layout(dock: .client, sizeMinimal: least), texture: nil,
                              items: items, controls: [], natural: .zero)
            return (root, sizingEdge)
        }

        /// One layout item, its children docked lowest `AlignLevel` first, and the controls
        /// `[Parents]` puts in it.
        mutating func item(_ source: AIMPNode) -> Shaped {
            let name: String
            if let given = source["Name"] {
                name = given
            } else {
                unnamed += 1
                name = "AIMP3Item\(unnamed)"
            }
            let dock = AIMPSkinDock(["top": "laTop", "bottom": "laBottom", "left": "laLeft", "right": "laRight", "client": "laClient"][
                source["Align"] ?? "top"] ?? "laTop")
            // Its level among its docked siblings, as AIMP's conversion writes it: the layout orders by
            // it, also where a form's or frame's own items come in another order.
            let level = Int(source["AlignLevel"] ?? "") ?? 0
            // The playlist frame's top dock is its caption while it floats: AIMP 5.40 shows it only
            // undocked (its conversion binds it `not PlaylistFrame.Docked`), and NullPlayer docks the
            // frame. NGuvu's 42-px caption over its 295-px bars, Bloom's 33-px one.
            let shown = !(name.caseInsensitiveCompare("PlsTopDock") == .orderedSame && framesReading.contains("playlistframe.xml"))
            let texture = picture(name) != nil ? name : nil
            var items: [Shaped] = []
            for child in source.children("item").enumerated()
                .sorted(by: { (Int($0.element["AlignLevel"] ?? "") ?? 0, $0.offset) < (Int($1.element["AlignLevel"] ?? "") ?? 0, $1.offset) }) {
                items.append(item(child.element))
            }
            var controls: [Spec] = []
            // A dock site's own minimum, which wins over the item's limits and its content's size.
            var siteMinimum: CGSize?
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
                    // With no bar of its own, the row is as tall as its tab.
                    if picture(name) == nil, let tab = picture("TabCtrlTab") {
                        siteMinimum = CGSize(width: 0, height: Int(tab.frameSize.height))
                    }
                } else if name == "Container" {
                    // An AIMP 3.0 skin's playlist takes no room of its own: AIMP 5.40 opens it at what its
                    // other parts take (Bloom's list, 0 px under its tab row; Pure White's and BYG's).
                    controls += playlistControls()
                }
            }
            // The item's own limits and resize flags (Experience's 176x301 cover panel, bars the user
            // cannot size); a site's minimum above wins.
            func size(_ key: String) -> CGSize? {
                let numbers = AIMPNode.numbers(source[key])
                return numbers.count == 2 ? CGSize(width: numbers[0], height: numbers[1]) : nil
            }
            func flag(_ key: String) -> Bool? { source[key].map { $0 != "0" } }
            var layout = Self.layout(dock: dock, level: level, margins: AIMPSkinImage.Margins(source["AlignMargins"]),
                                     sizeMinimal: siteMinimum ?? size("MinSize"), sizeMaximal: size("MaxSize"),
                                     autoSize: flag("AutoSize") ?? true, shown: shown,
                                     fixedWidth: flag("AllowResizeByWidth") == false, fixedHeight: flag("AllowResizeByHeight") == false)
            // An item with no picture is as big as what docks in it, and no smaller than its `MinSize`.
            let content = layout.floored(texture.flatMap { picture($0)?.frameSize } ?? Self.aggregate(items))
            if texture == nil, siteMinimum == nil, content.width > 0 || content.height > 0 {
                layout = layout.withMinimum(CGSize(width: Int(content.width), height: Int(content.height)))
            }
            controls += self.controls(in: name, size: content)
            let own = layout.floored(texture.flatMap { picture($0)?.frameSize } ?? Self.aggregate(items))
            return Shaped(name: name, layout: layout, texture: texture, items: items, controls: controls, natural: layout.slot(own))
        }

        /// What `items` take docked around each other, their clients over one another; a hidden one
        /// takes no room (the playlist frame's docked-away caption).
        static func aggregate(_ items: [Shaped]) -> CGSize {
            AIMPSkinAlignment.aggregate(items.filter(\.layout.savedShown).map { ($0.layout.dock, $0.natural) }, clients: .overlap)
        }

        /// An item's docking as AIMP 4 would declare it, nothing else said.
        static func layout(dock: AIMPSkinDock, level: Int = 0, margins: AIMPSkinImage.Margins? = nil, sizeMinimal: CGSize? = nil,
                           sizeMaximal: CGSize? = nil, autoSize: Bool = true, shown: Bool = true,
                           fixedWidth: Bool = false, fixedHeight: Bool = false) -> AIMPSkinItem.Layout {
            AIMPSkinItem.Layout(isTabbedGroup: false, dock: dock, level: level, margins: margins, size: nil, sizeMinimal: sizeMinimal,
                                sizeMaximal: sizeMaximal, autoHide: false, autoHideThreshold: nil, autoSize: autoSize, isRow: true,
                                savedShown: shown, fixedWidth: fixedWidth, fixedHeight: fixedHeight)
        }

        static func place(anchors: [Int], margins: [Int], size: CGSize) -> AIMPPlacement.Info {
            AIMPPlacement.Info(anchors: anchors, margins: margins, size: CGSize(width: Int(size.width), height: Int(size.height)))
        }

        /// The playlist tabs: NullPlayer has one playlist, its tab lit.
        func tabs() -> [Spec] {
            guard let tab = picture("TabCtrlTab") else { return [] }
            var spec = Spec(name: "PlaylistTab", placement: Self.place(anchors: [1, 1, 0, 0], margins: [0, 0, 0, 0], size: tab.frameSize))
            spec.type = .textDisplay
            spec.picture = "TabCtrlTab"
            spec.frame = tab.frameCount > 2 ? 2 : 0
            spec.caption = AIMPSkinList.playlistName
            spec.font = activeTab ?? "Tahoma,0,12,0"
            return [spec]
        }
    }
}

extension AIMPSkinItem.Layout {
    /// The same, no smaller than `minimum`.
    func withMinimum(_ minimum: CGSize) -> AIMPSkinItem.Layout {
        AIMPSkinItem.Layout(isTabbedGroup: isTabbedGroup, dock: dock, level: level, margins: margins, size: size, sizeMinimal: minimum,
                            sizeMaximal: sizeMaximal, autoHide: autoHide, autoHideThreshold: autoHideThreshold, autoSize: autoSize,
                            isRow: isRow, savedShown: savedShown, fixedWidth: fixedWidth, fixedHeight: fixedHeight)
    }
}
