import CoreGraphics
import CoreText
import Foundation
import os

/// A loaded AIMP skin: what the skin supplies, immutable, built off the main thread by
/// `AIMPSkinLoader`. Forms are trees of layout `item`s and `control`s
/// (`reference/layout.md`); `Schema.xml` is the resource repository they name textures, colours
/// and fonts through. Sendable: a window draws it on a background queue (`AIMPSkinFrameScheduler`).
struct AIMPSkin: Sendable {
    /// A form besides the main one: a skin's speakers, amplifier, equalizer unit, remote, playlist
    /// or library, in a window of its own unless a dock site holds it (`AIMPSkinDockSites`). Its info,
    /// lyrics and visualization frames are NullPlayer's own windows instead.
    struct Companion: Sendable {
        let name: String
        /// `DisplayName`, through the language strings.
        let title: String
        let initiallyVisible: Bool
        /// What the window holds, by its lists rather than its name (Akai GX-77's notepad playlist
        /// is `Win_1`).
        let role: Role
        /// False for a form NullPlayer has its own window for (Acubens' visualization): it shows
        /// only while docked.
        var opensWindow = true
        /// Where `Schema.xml` opens it beside its master (`Placement`), when it says.
        var declaredPlacement: DeclaredPlacement?
        /// Where it opens beside the deck when `Schema.xml` does not say: where the skin's layout puts
        /// it (AIMP 2's equalizer, right of the player), else from its name (`LSpeaker`,
        /// `SpeakerRightWindow`).
        let placement: Placement

        init(name: String, title: String, initiallyVisible: Bool, role: Role, placement: Placement? = nil) {
            self.name = name
            self.title = title
            self.initiallyVisible = initiallyVisible
            self.role = role
            self.placement = placement ?? AIMPFormRole.side(ofForm: name)
        }
        /// Where its window (`size`) opens beside the deck's window (`deck`), in screen coordinates
        /// (y up): as `Schema.xml` declares, its offset times `scale`, else by `placement`: beside
        /// the deck tops level (a speaker taller than the deck bottoms level), below it or above it
        /// at its left edge.
        func origin(size: CGSize, beside deck: CGRect, scale: CGFloat) -> CGPoint {
            if let declared = declaredPlacement {
                let offset = declared.offset * scale, centred = deck.midX - size.width / 2
                switch declared.side {
                case .left: return CGPoint(x: deck.minX - size.width, y: deck.maxY - offset - size.height)
                case .right: return CGPoint(x: deck.maxX, y: deck.maxY - offset - size.height)
                case .above: return CGPoint(x: centred, y: deck.maxY + offset)
                case .below: return CGPoint(x: centred, y: deck.minY - offset - size.height)
                }
            }
            var origin: CGPoint
            switch placement {
            case .left: origin = CGPoint(x: deck.minX - size.width, y: deck.maxY - size.height)
            case .right: origin = CGPoint(x: deck.maxX, y: deck.maxY - size.height)
            case .above: origin = CGPoint(x: deck.minX, y: deck.maxY)
            case .below: origin = CGPoint(x: deck.minX, y: deck.minY - size.height)
            }
            // Beside it only: a speaker below or above stays clear of the deck.
            if AIMPFormRole.isSpeaker(name), size.height > deck.height, placement == .left || placement == .right { origin.y = deck.minY }
            return origin
        }

        enum Role: Sendable { case playlist, library, other }
        enum Placement: Sendable { case left, above, right, below }

        /// A form's `Placement` in `Schema.xml`: `value` the side of its master it opens on (0 left,
        /// 1 above, 2 right, 3 below), `margins` (l, t, r, b) its offsets. A window beside the master
        /// stands `margins.t` below the master's top (Vilma M-212C's right speaker, -626: level with
        /// the deck's bottom); one above or below is centred on it, `margins.b` or `margins.t` clear
        /// of it (K-2's open glass lid and Sharp GF-777's handle stand on the deck).
        struct DeclaredPlacement: Equatable, Sendable {
            let side: Placement
            /// Down from the master's top, for a window beside it; the gap to it, above or below.
            let offset: CGFloat

            init?(_ node: AIMPNode?) {
                guard let node, let value = node["value"].flatMap(Int.init) else { return nil }
                let sides: [Placement] = [.left, .above, .right, .below]
                guard sides.indices.contains(value) else { return nil }
                let margins = AIMPNode.numbers(node["margins"] ?? "")
                side = sides[value]
                guard margins.count == 4 else { offset = 0; return }
                switch side {
                case .left, .right: offset = CGFloat(margins[1])
                case .above: offset = CGFloat(margins[3])
                case .below: offset = CGFloat(margins[1])
                }
            }
        }
    }

    let archive: AIMPSkinArchive
    let companions: [Companion]
    /// `Schema.xml`'s resources by `ID`.
    let resources: [String: AIMPSkinResource]
    /// The `.lng` strings for `@Lng:N;` captions: the user's language over English (`AIMPSkinLanguage`).
    let strings: [String: String]
    /// Decoded images by lowercased entry name; DPI variants (`-120`, `-144`…) are left out.
    let images: [String: AIMPSkinImage]
    let findings: [AIMPSkinFinding]
    /// Every script, compiled once as the skin loads (off the main thread): scripts run every
    /// frame while playing.
    let scripts: AIMPSkinScript.Library
    /// What the forms and `Schema.xml` declare, by name, built as the skin loads.
    let index: AIMPSkinIndex
    /// The fonts the skin ships, for its own text alone: its layout and its painter's canvas pass
    /// them to the font resolver (`AIMPSkinFont.ctFont(on:)`).
    var fontShelf: AIMPSkinFonts.Shelf? = nil
    /// Covers blurred for a `CoverArtDisplay`'s `BlurLevel`, kept while the skin is.
    let blurredCovers = AIMPSkinBlurredCovers()
    /// Each window's natural size, by form name (the main form's is ""), measured as the skin loads.
    fileprivate(set) var naturalSizes: [String: CGSize] = [:]

    /// The natural size of form `name` (nil: the main form).
    func naturalSize(form name: String?) -> CGSize? { naturalSizes[name ?? ""] }

    var name: String { archive.name }

    /// The companions that hold `role`'s list (or none of them, for `.other`), docked or not.
    func companions(_ role: Companion.Role) -> [Companion] { companions.filter { $0.role == role } }

    /// The resource `reference` names, through its aliases: `links` a script repointed, read before
    /// the skin's own, and a `Resource` holding no value that names another resource, by `link`
    /// (Vega MP-120's `Skin.BodyFace_` → `Skin.BodyFace_4`, its cassette sticker) or by `ID` (Soot's
    /// `clrTintFAB` → `clrTintFAB.D`). `id`: the name reached; `node`: its `Resource`, nil where the
    /// name is no resource (an image entry named directly, a font of AIMP's own theme); `chain`: each
    /// `Resource` passed on the way, the last first-named (a font's own settings override the one
    /// it names: Tascam Fireone's `Skin.Fonts.Header.SelectedFocused`, `Skin.Fonts.Common.Title` in
    /// white). One resolver for images, colours and fonts.
    static func resource(_ reference: String?, in resources: [String: AIMPSkinResource], links: [String: String] = [:])
        -> (id: String, entry: AIMPSkinResource.Entry?, chain: [AIMPSkinResource.Entry])? {
        guard var name = reference, !name.isEmpty else { return nil }
        var chain: [AIMPSkinResource.Entry] = []
        // Every redirect is followed to the end of its chain, however long; one that comes back to a
        // name already passed is a loop, and names nothing. Most chains are a step or two: the names
        // passed are only kept from the eighth on.
        var passed: Set<String> = [], steps = 0
        while true {
            steps += 1
            if steps > 8, !passed.insert(name).inserted { return nil }
            if let link = links[name] {
                name = link
                continue
            }
            guard let entry = resources[name]?.entry else { return (name, nil, chain) }
            chain.insert(entry, at: 0)
            // One naming itself is itself (M5's `Skin.Fonts.Buttons.Dark`).
            guard !entry.holdsValue, let alias = entry.alias, alias != name else { return (name, entry, chain) }
            name = alias
        }
    }

    /// The image a skin, texture or resource reference names (`resource(_:in:links:)`): the entry
    /// is the resource's `value`, else the name itself, as `<name>.img` or `<name>Resource.img`
    /// (`.acs4`'s naming). `links` are aliases a script repointed.
    func image(_ reference: String?, links: [String: String] = [:]) -> AIMPSkinImage? {
        guard let (id, entry, _) = Self.resource(reference, in: resources, links: links) else { return nil }
        let name = entry?.value.flatMap { $0.isEmpty ? nil : $0 } ?? id
        guard let image = images[(name + ".img").lowercased()] ?? images[(name + "Resource.img").lowercased()] else { return nil }
        // A texture resource coloured by a colour resource (`AllowColoration`, `ColorID`), through
        // the theme's aliases: M5's panels and windows, light or dark.
        if entry?.allowsColoration == true, let id = entry?.colorID, let argb = Self.color(id, in: resources, links: links) {
            return image.tinted(argb)
        }
        return image
    }

    /// A `TACLResourceColor` by `ID`, as ARGB, through its aliases (`resource(_:in:links:)`).
    /// `clrNone` and unknown IDs are nil.
    static func color(_ reference: String?, in resources: [String: AIMPSkinResource], links: [String: String] = [:]) -> UInt32? {
        guard let argb = Self.resource(reference, in: resources, links: links)?.entry?.number else { return nil }
        return UInt32(truncatingIfNeeded: argb)
    }

    /// A `Color` property's ARGB (`AIMPSkinColor`), through the resource aliases a script repointed.
    func color(_ color: AIMPSkinColor?, links: [String: String] = [:]) -> UInt32? {
        switch color {
        case .argb(let argb): return argb
        case .resource(let name): return Self.color(name, in: resources, links: links)
        case nil: return nil
        }
    }
}

/// Artwork blurred by a `CoverArtDisplay`'s `BlurLevel` (Soot's backdrop): the same cover blurs the
/// same way every frame, so the last few are kept, one set per skin (`AIMPSkinCache`).
final class AIMPSkinBlurredCovers: Sendable {
    private let made = AIMPSkinCache<Key, Blurred>(limit: 4)

    /// A cover by identity: the entry holds the cover, so no other picture takes its identity while
    /// the entry is kept.
    private struct Key: Hashable, Sendable {
        let cover: ObjectIdentifier
        let level: Double
    }

    private struct Blurred: Sendable {
        let cover: CGImage
        let image: CGImage?
    }

    /// `cover` at `level`, as `blur` makes it, made once.
    func image(_ cover: CGImage, level: Double, blur: () -> CGImage?) -> CGImage? {
        made.value(Key(cover: ObjectIdentifier(cover), level: level)) { Blurred(cover: cover, image: blur()) }.image
    }
}

enum AIMPSkinLoader {
    /// The font files one skin's shelf holds together: M5's three families are a few MB, so a skin
    /// whose fonts sum past this is a bomb, not a type specimen.
    static let fontBytes = 256 * 1_024 * 1_024
    /// The suffixes of a picture's DPI variants (`Meter-120`); any other number is the picture's own
    /// name (`Meter-2`).
    static let dpiSuffixes: Set<String> = ["120", "144", "168", "192"]

    /// The production entry point: leaves the caller's executor before the file is touched, for a
    /// thread with the stack a skin's layout needs (`AIMPSkinWorker`).
    static func load(file: URL) async throws -> AIMPSkin {
        try await AIMPSkinWorker.run { try load(contentsOf: file) }
    }

    static func load(contentsOf file: URL) throws -> AIMPSkin {
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            throw AIMPSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        guard size <= AIMPSkinPolicy.fileBytes else {
            throw AIMPSkinFinding(.fileTooLarge, "\(size) bytes, more than \(AIMPSkinPolicy.fileBytes).")
        }
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else {
            throw AIMPSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        return try load(data: data)
    }

    /// Which reader a skin's forms take, decided once from its archive: AIMP 4 and 5's markup forms
    /// (`AIMPMainForm.xml`, whatever the container), AIMP 3.0's `main.ini` and layout
    /// (`AIMPSkinAIMP3`), or AIMP 2's `main.ini` in an `ACSP` container (`AIMPSkinAIMP2`).
    private enum Generation {
        case markup(AIMPNode)
        case aimp3(INIFile)
        case aimp2(INIFile)

        var isMarkup: Bool { if case .markup = self { true } else { false } }
        var isAIMP2: Bool { if case .aimp2 = self { true } else { false } }
    }

    /// `languages`: the preferred languages, most wanted first, that `@Lng:N;` captions are read in.
    static func load(data: Data, languages: [String] = Locale.preferredLanguages) throws -> AIMPSkin {
        let archive = try AIMPSkinArchive.read(data)
        // Every document is read through one reader, which keeps what does not read as a finding.
        let documents = AIMPSkinDocuments(archive)

        // An AIMP 3.0 skin has no form documents: its form is read from its layout and `main.ini` once
        // the pictures it is sized by are read (`AIMPSkinAIMP3`).
        let generation: Generation
        if let ini = archive.mainINI {
            generation = archive.format == .acsp ? .aimp2(ini) : .aimp3(ini)
        } else {
            generation = .markup(try documents.throwing("AIMPMainForm.xml", missing: "The skin has no AIMPMainForm.", documents.node))
        }

        let strings = AIMPSkinLanguage.strings(in: documents, preferred: languages)

        // The fonts it ships (M5's Segoe Fluent Icons, Poppins and Segoe UI), for the faces it names,
        // in name order: which file names a family is the same every load. The shelf holds every
        // file it is given, so they are held to `fontBytes` together; the ones past it are left out.
        var fontBytes = 0
        let fontShelf = AIMPSkinFonts.shelf(archive.entries.sorted { $0.key < $1.key }
            .filter { $0.key.hasSuffix(".ttf") || $0.key.hasSuffix(".otf") }
            .compactMap { entry -> Data? in
                guard fontBytes + entry.value.declaredSize <= Self.fontBytes else { return nil }
                do {
                    let data = try archive.payload(entry.value)
                    fontBytes += data.count
                    return fontBytes <= Self.fontBytes ? data : nil
                } catch {
                    // A font that does not inflate is left out, and said so (`AM0008`).
                    documents.record(error as? AIMPSkinFinding ?? AIMPSkinFinding(.entryUnreadable, "\(entry.key): \(error)"))
                    return nil
                }
            })

        // Pictures are read from their headers here and decode when first drawn, within one
        // budget of resident pixels (`AIMPSkinPixelBudget`). DPI variants end in -120, -144, -168,
        // -192. Older skins name the same pictures `.myimg` (Sony TC-MR2), AIMP 3.0's BMP skins `.bmp`,
        // cut as `main.ini` says; each is filed as `.img`, which wins, then `.myimg`.
        let budget = AIMPSkinPixelBudget()
        // AIMP 2's bitmaps are laid out as its form is read (`AIMPSkinAIMP2.layOut`).
        let layouts: [String: AIMPSkinImage.Layout]
        if case .aimp3(let ini) = generation { layouts = AIMPSkinAIMP3.bitmapLayouts(ini) } else { layouts = [:] }
        var images: [String: AIMPSkinImage] = [:]
        var inflated = 0
        for (name, entry) in archive.entries.sorted(by: { $0.key < $1.key }) {
            guard let ext = [".img", ".myimg", ".bmp"].first(where: name.hasSuffix), !generation.isMarkup || ext != ".bmp" else { continue }
            let stem = String(name.dropLast(ext.count))
            if ext != ".img", archive.entries[stem + ".img"] != nil { continue }
            if ext == ".bmp", archive.entries[stem + ".myimg"] != nil { continue }
            if let dash = stem.lastIndex(of: "-"), Self.dpiSuffixes.contains(String(stem[stem.index(after: dash)...])) { continue }
            inflated += entry.declaredSize
            guard inflated <= AIMPSkinPolicy.loadInflatedBytes else {
                throw AIMPSkinFinding(.inflatedTooLarge, "The pictures inflate past \(AIMPSkinPolicy.loadInflatedBytes) bytes.")
            }
            do {
                let payload = try archive.payload(entry)
                let source = { try archive.payload(entry) }
                let image = ext == ".bmp"
                    ? try AIMPSkinImage(bitmap: payload, name: entry.name, layout: layouts[stem] ?? .init(), budget: budget, source: source)
                    : try AIMPSkinImage(payload, name: entry.name, budget: budget, source: source)
                // AIMP 2's are cut into frames as its form is read: their frames are checked then.
                if !generation.isAIMP2 { try Self.checkFrames(of: image, name: entry.name) }
                guard image.width * image.height <= budget.limit else {
                    throw AIMPSkinFinding(.pixelBudgetExceeded,
                                          "\(entry.name) alone has \(image.width * image.height) pixels, more than \(budget.limit).")
                }
                images[stem + ".img"] = image
            } catch let finding as AIMPSkinFinding where finding.code == .entryUnreadable {
                documents.record(finding)
            }
        }

        var scriptFindings: [AIMPSkinFinding] = []
        let scripts = try AIMPSkinScript.Library(archive, inflated: &inflated, findings: &scriptFindings)
        scriptFindings.forEach(documents.record)
        let companions: [AIMPSkin.Companion], resources: [String: AIMPSkinResource], index: AIMPSkinIndex
        switch generation {
        case .markup(let mainForm):
            (companions, resources, index) = Self.markupForms(mainForm, documents: documents, strings: strings)
        case .aimp2(let ini):
            resources = [:]
            (index, companions, images) = try AIMPSkinAIMP2(documents: documents, ini: ini, images: images, strings: strings)
                .read(dialect: AIMPSkinDialect(archive))
            for (name, image) in images.sorted(by: { $0.key < $1.key }) { try Self.checkFrames(of: image, name: name) }
        case .aimp3(let ini):
            (companions, resources) = ([], [:])
            index = try AIMPSkinAIMP3.read(documents, ini: ini, images: images, strings: strings, dialect: AIMPSkinDialect(archive))
        }
        var skin = AIMPSkin(archive: archive, companions: companions, resources: resources,
                        strings: strings, images: images, findings: documents.findings, scripts: scripts, index: index)
        skin.fontShelf = fontShelf
        // Each window's natural size, measured with trial frames here, off the main thread, rather
        // than when the window shows the skin.
        // A schema listing one form twice must not trap here: the first measure is kept.
        skin.naturalSizes = Dictionary(([nil] + companions.map(\.name)).compactMap { form in
            AIMPSkinRenderer.naturalSize(skin, form: form).map { (form ?? "", $0) }
        }, uniquingKeysWith: { first, _ in first })
        return skin
    }

    /// AM0006: each of `image`'s frames at most `imageSide` each way.
    private static func checkFrames(of image: AIMPSkinImage, name: String) throws {
        let frame = image.frameSize
        guard frame.width <= CGFloat(AIMPSkinPolicy.imageSide), frame.height <= CGFloat(AIMPSkinPolicy.imageSide) else {
            throw AIMPSkinFinding(.imageTooLarge, "\(name) has \(Int(frame.width))×\(Int(frame.height)) frames.")
        }
    }

    /// A skin's XML forms and `Schema.xml`: the windows beside the main form, the resources, and the
    /// index of them all.
    private static func markupForms(_ mainForm: AIMPNode, documents: AIMPSkinDocuments, strings: [String: String])
        -> (companions: [AIMPSkin.Companion], resources: [String: AIMPSkinResource], index: AIMPSkinIndex) {
        let archive = documents.archive
        let schema = documents.node("Schema.xml")
        var resources: [String: AIMPSkinResource] = [:]
        for item in schema?.child("properties")?.child("resources")?.children("item") ?? [] {
            let properties = item.named
            if let id = properties["ID"]?["value"] { resources[id] = AIMPSkinResource(properties) }
        }
        var companions: [AIMPSkin.Companion] = []
        // Each companion's form, the first of a name.
        var forms: [String: AIMPNode] = [:]
        // `Schema.xml` lists the forms; the ones NullPlayer has its own window for stay out, and so
        // does TC-MR2's `Menu`, a popup its MENU key stands in for with NullPlayer's. The skin's own
        // playlist and library windows open, over NullPlayer's playlist and library.
        // A skin's own cover window (Tascam CD-RW2000's, AIMP-Cassette's) has no NullPlayer twin: it opens.
        for entry in schema?.child("forms")?.children("form") ?? [] {
            guard let name = entry["name"], entry["master"] == "AIMPMainForm",
                  !AIMPFormRole(name).isNullPlayers,
                  let form = documents.node(name + ".xml") else { continue }
            let props = entry.properties.mapValues { $0["value"] ?? "" }
            let links = Set(form.descendants().compactMap { $0["link"] })
            let role: AIMPSkin.Companion.Role = links.contains("MLTable") || links.contains("MLGroupingTree") ? .library
                : links.contains("Playlist") ? .playlist : .other
            let title = props["DisplayName"].map { AIMPSkinLanguage.expanded($0, strings: strings) } ?? AIMPFormRole.title(ofForm: name, role: role)
            var companion = AIMPSkin.Companion(name: name, title: title, initiallyVisible: props["InitialVisible"] != "False", role: role)
            companion.declaredPlacement = .init(entry.properties["Placement"])
            companions.append(companion)
            if forms[name] == nil { forms[name] = form }
        }
        // A dock site may hold one of the forms NullPlayer has its own window for (Acubens'
        // visualization and file info): it joins the companions, shown only while docked.
        let sites = AIMPSkinDockSites.sites(in: mainForm) { name in
            if let form = forms[name] { return form }
            guard let form = documents.node(name + ".xml") else { return nil }
            var companion = AIMPSkin.Companion(name: name, title: AIMPFormRole.title(ofForm: name, role: .other),
                                               initiallyVisible: true, role: .other)
            companion.opensWindow = false
            companions.append(companion)
            forms[name] = form
            return form
        }
        let unopened = (schema?.child("forms")?.children("form") ?? []).compactMap { entry -> (name: String, form: AIMPNode?)? in
            guard let name = entry["name"], name != "AIMPMainForm", !companions.contains(where: { $0.name == name }) else { return nil }
            return (name, documents.node(name + ".xml"))
        }
        let index = AIMPSkinIndex(main: mainForm, companions: companions, forms: forms, schema: schema, sites: sites,
                                  resources: resources, strings: strings, unopened: unopened,
                                  dialect: AIMPSkinDialect(archive))
        return (companions, resources, index)
    }
}
