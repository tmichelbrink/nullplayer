import CoreGraphics
import Foundation

// The items and bindings of a skin's XML forms, read into the model (`AIMPSkinItem`, `AIMPSkinBindings`).

extension AIMPSkinItem {
    convenience init(_ node: AIMPNode, compile: (AIMPNode) -> AIMPSkinControl, names: AIMPSkinIndex.Names) {
        let props = node.properties
        let order = node.children.map(\.tag)
        self.init(name: node["name"], className: node["class"], isItem: node.tag == "item", layout: Layout(node),
                  bindings: AIMPSkinBindings(node, names: names), texture: props["Texture"]?.reference,
                  color: AIMPSkinColor(props["Color"]), declaresColor: !(props["Color"]?.reference ?? "").isEmpty,
                  items: (node.child("items")?.children("item") ?? []).map { AIMPSkinItem($0, compile: compile, names: names) },
                  controls: (node.child("controls")?.children("control") ?? []).map(compile),
                  itemsFirst: (order.firstIndex(of: "items") ?? .max) < (order.firstIndex(of: "controls") ?? .max),
                  tag: props["Tag"]?["value"], writtenMargins: AIMPNode.writtenNumbers(props["PlaceInfo"]?["margins"]))
    }
}

extension AIMPSkinItem.Layout {
    init(_ node: AIMPNode) {
        let props = node.properties
        isTabbedGroup = node["class"] == "LayoutTabbedGroup"
        dock = props["Alignment"].map { AIMPSkinDock($0.reference) }
        level = Int(props["AlignmentLevel"]?.reference ?? "") ?? 0
        margins = AIMPSkinImage.Margins(props["AlignmentMargins"]?.reference)
        size = Self.size(props["Size"]?.reference)
        sizeMinimal = Self.size(props["SizeMinimal"]?.reference)
        sizeMaximal = Self.size(props["SizeMaximal"]?.reference)
        autoHide = props["AutoHide"]?.reference == "True"
        autoHideThreshold = Double(props["AutoHideParentSizeThreshold"]?.reference ?? "").flatMap { $0 > 0 ? $0 : nil }
        autoSize = props["AutoSize"]?.reference != "False"
        isRow = props["LayoutDirection"]?.reference != "ldVertical"
        fixedWidth = props["AllowResizeByWidth"]?.reference == "False"
        fixedHeight = props["AllowResizeByHeight"]?.reference == "False"
        savedShown = (props["Visible"]?.reference != "False" && props["InitialVisible"]?.reference != "False") || autoHide
    }

    /// "w,h": two numbers, else nil.
    private static func size(_ text: String?) -> CGSize? {
        let numbers = AIMPNode.numbers(text)
        return numbers.count == 2 ? CGSize(width: numbers[0], height: numbers[1]) : nil
    }
}

extension AIMPSkinLink {
    init(_ node: AIMPNode, names: AIMPSkinIndex.Names) {
        self.init(source: node["Source"], pin: node["SourcePin"], target: node["TargetPin"], expression: node["Expression"],
                  textFormat: node["TextFormat"], names: names)
    }
}

extension AIMPSkinBindings {
    init(_ node: AIMPNode, names: AIMPSkinIndex.Names) {
        let property = node.properties["Bindings"]
        let links = (property?.children("link") ?? []).flatMap { link -> [AIMPSkinLink] in
            // A link that names only an action (`<link Source="acPlayerPlayPause"/>`, AIMP 3 skins'
            // AyonPlayer) binds the control to it: its Action, and its State for a key that lights.
            guard let source = link["Source"], link["SourcePin"] == nil, link["TargetPin"] == nil, AIMPAction(source) != nil else {
                return [AIMPSkinLink(link, names: names)]
            }
            // Its other attributes come along (`Expression="not Value"` shapes the lamp).
            return ["Action", "State"].map { pin in
                AIMPSkinLink(source: source, pin: pin, target: pin, expression: link["Expression"], textFormat: link["TextFormat"], names: names)
            }
        }
        self.init(links: links, declared: property != nil)
    }
}
