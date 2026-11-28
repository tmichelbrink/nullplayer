import Foundation

/// A `Schema.xml` resource (`TACLResource…` item), read once as the skin loads: what images, colours
/// and fonts are resolved through every frame (`AIMPSkin.resource(_:in:links:)`), and the settings a
/// script reads back (`FindResource('Skin.Default').Get('Value')`).
struct AIMPSkinResource: Sendable {
    /// Its `Resource` property, which names a picture, a colour or a font, or another resource; nil
    /// for an item without one (a name that is no resource).
    let entry: Entry?
    /// Each of its properties' value (`value`, else a nested `Value`'s), by name.
    let settings: [String: String]

    struct Entry: Sendable {
        /// Its `value`: an image entry's name, a colour's number.
        let value: String?
        /// Whether it holds a value (`value`, or a nested `Value`), rather than naming another.
        let holdsValue: Bool
        /// The resource it names when it holds no value: its `link` (Vega MP-120's `Skin.BodyFace_`
        /// → `Skin.BodyFace_4`), else its nested `ID` (Soot's `clrTintFAB` → `clrTintFAB.D`).
        let alias: String?
        /// A colour's ARGB number: its nested `Value`, else its first property's value.
        let number: Int64?
        /// A texture coloured by a colour resource (`AllowColoration` 1, `ColorID`): M5's panels.
        let allowsColoration: Bool
        let colorID: String?
        /// `MaskFrame` and `CoverFrame` a control's `Skin` takes when it gives none (Windows Media
        /// Player 11's gloss, frame 2, over its cover).
        let maskFrame: String?
        let coverFrame: String?
        /// What it declares of a font (`TASEFont`).
        let font: AIMPSkinFont.Declaration
    }
}

extension AIMPSkinFont {
    /// What a font property declares (`Name`, `Height`, `Style`, `Color`: each one present counts,
    /// empty or not), and its `ColorID`.
    struct Declaration: Sendable {
        let values: [String: String]
        let colorID: String?
    }
}

// MARK: - Read from the skin's XML

extension AIMPSkinResource {
    /// A `Schema.xml` resource item's properties, by name.
    init(_ properties: [String: AIMPNode]) {
        entry = properties["Resource"].map(Entry.init)
        settings = properties.mapValues { $0["value"] ?? $0.named["Value"]?["value"] ?? "" }
    }
}

extension AIMPSkinResource.Entry {
    init(_ node: AIMPNode) {
        value = node["value"]
        holdsValue = !(node["value"] ?? "").isEmpty || node.named["Value"] != nil
        // An empty `link` names nothing: the nested `ID` does (`link=""` beside it).
        alias = [node["link"], node.named["ID"]?["value"]].lazy.compactMap { $0 }.first { !$0.isEmpty }
        number = (node.named["Value"] ?? node.child("property")).flatMap { $0["value"] }.flatMap { Int64($0) }
        allowsColoration = node["AllowColoration"] == "1"
        colorID = node["ColorID"]
        maskFrame = node["MaskFrame"]
        coverFrame = node["CoverFrame"]
        font = AIMPSkinFont.Declaration(node)
    }
}

extension AIMPSkinFont.Declaration {
    init(_ node: AIMPNode) {
        values = node.named.mapValues { $0["value"] ?? "" }
        colorID = node.named["ColorID"]?["value"]
    }

    /// Which of `Name`, `Height`, `Style` and `Color` it sets, as `AIMPSkinFont(declared:over:)` reads them.
    var declaredSettings: AIMPSkinFont.Settings {
        var settings: AIMPSkinFont.Settings = []
        if let name = values["Name"], !name.isEmpty { settings.insert(.name) }
        if let height = values["Height"].flatMap(Int.init), height != .min { settings.insert(.height) }
        if values["Style"] != nil { settings.insert(.style) }
        if values["Color"].flatMap({ Int64($0) }) != nil { settings.insert(.color) }
        return settings
    }
}
