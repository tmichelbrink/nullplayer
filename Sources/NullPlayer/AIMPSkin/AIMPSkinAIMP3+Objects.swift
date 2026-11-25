import CoreGraphics
import Foundation

extension AIMPSkinAIMP3.Shape {
    /// The controls in `item`, back to front, less those parked.
    func controls(in item: String, size: CGSize) -> [AIMPSkinAIMP3.Spec] {
        (objects[item.lowercased()] ?? []).flatMap { object -> [AIMPSkinAIMP3.Spec] in
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
    func control(_ object: AIMPSkinAIMP3.Object) -> [AIMPSkinAIMP3.Spec] {
        typealias Spec = AIMPSkinAIMP3.Spec
        let name = object.name
        var spec = Spec(name: name, placement: Self.place(anchors: object.anchors, margins: object.margins, size: object.size))
        if picture(name) != nil { spec.picture = name }
        let thumb = picture(name + "_thumb") != nil
        func bind(_ source: String, _ pin: String, _ target: String) { spec.links.append(.init(source: source, pin: pin, target: target)) }
        func align() { spec.alignment = [1: "taRightJustify", 2: "taCenter"][object.textAlign ?? 0] }
        // Its picture with nothing playing, the display over it.
        func backed(_ front: Spec) -> [Spec] {
            var back = spec
            back.type = .textDisplay
            back.links = []
            back = Spec(renamed: back, name + "Back")
            return [back, front]
        }
        switch object.kind {
        case .text(let template):
            spec.type = .textDisplay
            if template.contains("%") {
                spec.template = template
                bind("prvPlayingFileInfo", "FileInfo", "DisplayValue")
            } else {
                spec.caption = template
            }
            spec.font = object.font
            align()
        case .time(let time, let digits, let indent):
            spec.type = .timeDisplay
            (spec.digits, spec.indent) = (digits, indent)
            switch time {
            case .duration: bind("prvPlayerState", "TrackDuration", "DisplayValue")
            case .remaining: bind("prvPlayerState", "TrackPositionRemaining", "DisplayValue")
            case .position: bind("prvPlayerState", "TrackPosition", "DisplayValue")
            // The sleep timer reads zero: its value pinned by an expression.
            case .sleepTimer: spec.links.append(.init(source: "prvPlayerState", pin: "TrackPosition", target: "DisplayValue", expression: "0"))
            }
        case .bitrate:
            spec.type = .digitsDisplay
            bind("prvPlayingFileInfo", "Bitrate", "DisplayValue")
        case .sampleRate:
            spec.type = .digitsDisplay
            bind("prvPlayingFileInfo", "SampleRate", "DisplayValue")
        case .status(let showsState):
            // A picture per state: stopped, playing, paused.
            spec.type = .digitsDisplay
            spec.digits = "1"
            if showsState { bind("prvPlayerState", "State", "DisplayValue") }
        case .seekBar:
            spec.type = .seekBar
            if thumb { spec.thumb = name + "_thumb" }
        case .animator(let interval):
            // AIMP 3 runs them all the time (Vega's logo turns while stopped; a lamp over it hides
            // it while playing).
            spec.type = .animator
            spec.interval = interval
            bind("AIMPMainForm", "Visible", "Accessibility")
        case .spectrum(let peaks, let indent, let colour, let flipped, let masked):
            var bars = Spec(name: name, placement: spec.placement)
            bars.type = .spectrum
            (bars.columns, bars.columnsIndent, bars.flipped) = (peaks, indent, flipped)
            // With `SkinHitTestMask` 1 the picture is the bars, lit up to each one's level and see-through
            // elsewhere (GREEX's fifty spectra a pixel apart, black bars smeared into one shape over
            // its blue display; Aero Style's dark bars on glass): no backdrop, no `Color`.
            if masked, picture(name) != nil {
                bars.peakColumns = name
                return [bars]
            }
            // Its picture is the empty display; the bars are `Color` (a Delphi colour), `Peaks` of them.
            bars.color = colour.map(AIMPSkinColor.argb(delphi:))
            return backed(bars)
        case .coverArt:
            var cover = Spec(name: name, placement: spec.placement)
            cover.type = .coverArt
            return backed(cover)
        case .equalizerDisplay(let curve, let preamp):
            // Its picture is the grid; the curve is `EQVISE`, the preamp line `EQVISL`.
            spec.type = .equalizer
            spec.curve = curve.map(AIMPSkinColor.argb(delphi:))
            spec.preamp = preamp.map(AIMPSkinColor.argb(delphi:))
        case .object("multidisplay"):
            // The visualization screen: its picture (QMP 5's logo) shows when none runs, the
            // visualization over it otherwise; VisPrev and VisNext step it.
            var screen = Spec(name: name, placement: spec.placement)
            screen.type = .visualDisplay
            return backed(screen)
        case .object(let key):
            guard aimpObject(key, thumb: thumb, orientation: object.orientation, into: &spec) else { return [] }
            if key == "infobar" || key == "countlabel" || key == "lengthlabel" { spec.font = object.font }
            if key == "countlabel" || key == "lengthlabel" { align() }
        }
        return [spec]
    }

    /// AIMP's own object `key` as `spec`'s class and bindings; false for an object NullPlayer has no
    /// counterpart for and that draws nothing.
    private func aimpObject(_ key: String, thumb: Bool, orientation: Int?, into spec: inout AIMPSkinAIMP3.Spec) -> Bool {
        func bind(_ source: String, _ pin: String, _ target: String) { spec.links.append(.init(source: source, pin: pin, target: target)) }
        if let action = Self.actions[key] {
            bind(action, "Action", "Action")
        } else if key == "playpausebtn" {
            // Play's four frames, then pause's, shown while playing.
            spec.framesPerState = 4
            bind("acPlayerPlayPause", "Action", "Action")
            bind("prvPlayerState", "State", "State")
        } else if let action = Self.switches[key] {
            spec.type = .toggle
            spec.framesPerState = 3
            bind(action, "Action", "Action")
        } else if let menu = Self.menus[key] {
            spec.popupMenu = menu
        } else if let provider = Self.sliders[key] ?? (key == "preamp" || key.hasPrefix("aimpslider") ? "prvEqualizer" : nil) {
            // `Orientation` 0 upright, 1 across, 2 a knob turned through its frames.
            spec.type = orientation == 2 ? .sliderMasked : orientation == 1 ? .slider : .sliderVertical
            if thumb, spec.type != .sliderMasked { spec.thumb = spec.name + "_thumb" }
            bind(provider, key == "preamp" ? "Preamp" : key.hasPrefix("aimpslider") ? "Band" + key.dropFirst(10) : "Action", "Action")
        } else if let provider = Self.effects[key] {
            // AIMP's sound effects (Experience's FLANGER, REVERB, CHORUS, ECHO): NullPlayer has none,
            // so they rest at off (`AIMPSkinHostState`).
            spec.type = orientation == 0 ? .sliderVertical : .slider
            if thumb { spec.thumb = spec.name + "_thumb" }
            bind(provider, "Action", "Action")
        } else if key == "infobar" {
            spec.type = .runningLine
        } else if key == "countlabel" || key == "lengthlabel" {
            spec.type = .textDisplay
            bind("Playlist", key == "countlabel" ? "Count" : "Duration", "DisplayValue")
            if key == "lengthlabel" { spec.template = "%time(HMS;:;)" }
        } else if spec.picture == nil {
            return false
        }
        return true
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
    /// AIMP's sound-effect sliders, which have no NullPlayer counterpart.
    private static let effects = ["chorus": "prvChorus", "flanger": "prvFlanger", "echo": "prvEcho", "reverb": "prvReverb"]
    private static let menus = ["menubtn": "pmMenu", "addbtn": "pmAdd", "delbtn": "pmDelete", "sortbtn": "pmSort",
                                "miscbtn": "pmMisc", "plsopt": "pmPlaylist", "btnplaylistslistmenu": "pmPlaylists"]

    // MARK: - Playlist

    /// The playlist in `[Playlist]`'s fonts and colours, its scroll bar down the right.
    func playlistControls() -> [AIMPSkinAIMP3.Spec] {
        var resources: [String: String] = [:]
        // AIMP 3 draws a track on two lines, the title in the `…Hdr` font and the details under it in
        // the plain one; NullPlayer's one line is the title. A title colour of 0 is AIMP's automatic
        // one, light over a dark row and dark over a light one (GREEX's white titles on blue,
        // Aero Style's black on white glass): the row's own fill where it has one.
        let dark = listIsDark()
        let rows: [(resource: String, title: String, details: String, fill: String?)] = [
            ("ItemLine1Font", "NrmHdr", "Nrm", nil), ("ItemLine1FontPlaying", "ActHdr", "Act", "ABK"),
            ("ItemLine1FontSelected", "SelHdr", "Sel", "SBK"),
            ("ItemLine1FontPlayingSelected", "SelActHdr", "SelAct", playlist["SABK"] == nil ? "SBK" : "SABK"),
        ]
        for (resource, title, details, fill) in rows {
            if let font = playlist[title] {
                resources[resource] = Self.automaticColour(font, dark: rowIsDark(fill, list: dark))
            } else if let font = playlist[details] {
                resources[resource] = font
            }
        }
        // The details under it, in the plain fonts; a group's header in `Header`.
        for (resource, key) in [("ItemLine2Font", "Nrm"), ("ItemLine2FontPlaying", "Act"), ("ItemLine2FontSelected", "Sel"),
                                ("ItemLine2FontPlayingSelected", "SelAct"), ("HeaderFont", "Header")] {
            if let font = playlist[key] { resources[resource] = font }
        }
        for (resource, name) in [("HeaderExpandButtons", "PlaylistExpandButtons"), ("ItemSwitches", "PlaylistSwitches"),
                                 ("ItemMarks", "PlaylistRating")] where picture(name) != nil {
            resources[resource] = name
        }
        for (resource, key) in [("BackgroundColor", "BK"), ("ItemHighlightColorPlaying", "ABK"),
                                ("ItemHighlightColorSelected", "SBK"), ("ItemHighlightColorSelectedPlaying", "SABK")] {
            if let value = playlist[key] { resources[resource] = value }
        }
        let bar = Int(picture("PlaylistScroll")?.frameSize.width ?? 0)
        // `PlaylistWallpaper` is the list's background where the skin has one (GREEX's blue, Aero
        // Style's white glass; 14 of the catalogue's AIMP 3 skins), over `BK`.
        if picture("PlaylistWallpaper") != nil { resources["Skin"] = "PlaylistWallpaper" }
        var list = AIMPSkinAIMP3.Spec(name: "Playlist", placement: Self.place(anchors: [1, 1, 1, 1], margins: [0, 0, bar, 0], size: .zero))
        list.type = .panel
        list.isPlaylist = true
        list.playlist = resources
        guard bar > 0 else { return [list] }
        var scroll = AIMPSkinAIMP3.Spec(name: "PlaylistScroll",
                                        placement: Self.place(anchors: [0, 1, 1, 1], margins: [0, 0, 0, 0], size: CGSize(width: bar, height: 0)))
        scroll.type = .scrollBar
        scroll.picture = "PlaylistScroll"
        scroll.links = [.init(source: "Playlist", pin: "Position", target: "Action")]
        if picture("PlaylistScroll_thumb") != nil { scroll.thumb = "PlaylistScroll_thumb" }
        return [list, scroll]
    }

    /// Whether a row with the fill `key` names (`ABK`, `SBK`, `SABK`) is dark: its own fill where the
    /// skin gives one, else the list's (Hysteria's playing row, light grey on its dark list, takes
    /// black titles).
    private func rowIsDark(_ key: String?, list: Bool) -> Bool {
        guard let key, let bgr = playlist[key].flatMap({ Int($0) }) else { return list }
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
        let bgr = playlist["BK"].flatMap { Int($0) } ?? 0
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
}

extension AIMPSkinAIMP3.Spec {
    /// `spec` under another name.
    init(renamed spec: AIMPSkinAIMP3.Spec, _ name: String) {
        self = spec
        self.name = name
    }
}
