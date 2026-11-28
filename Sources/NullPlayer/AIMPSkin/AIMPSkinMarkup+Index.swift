import CoreGraphics
import Foundation

// A skin's XML forms and `Schema.xml`, read into the index (`AIMPSkinIndex`): the tables links and
// scripts read, then the forms themselves.

extension AIMPSkinIndex {
    /// `unopened`: the forms the skin declares that NullPlayer opens no window for, by name, with
    /// their document where the skin has one. Their items are known, though never laid out: what
    /// they hold still reads as AIMP keeps it (AIMP Modern v3.63's visualizer modes are the pages of
    /// a tabbed group in its hidden `QFI` form, the first shown).
    init(main: AIMPNode, companions: [AIMPSkin.Companion], forms: [String: AIMPNode] = [:], schema: AIMPNode?, sites: [String: AIMPSkinDockSites.Marked] = [:],
         resources: [String: AIMPSkinResource] = [:], strings: [String: String] = [:],
         unopened: [(name: String, form: AIMPNode?)] = [],
         dialect: AIMPSkinDialect = .modern) {
        self.init(names: Names(), companions: companions, sites: sites.mapValues(\.site),
                  sizing: Self.sizing(main: main, companions: companions, schema: schema),
                  resources: resources, strings: strings, dialect: dialect)
        let nodes = ([main] + companions.compactMap { forms[$0.name] }).flatMap { $0.descendants() }
        let schemaNodes = schema?.descendants() ?? []
        // Providers ask too (M5's delayer swaps its wave bar's times for its hover page while the
        // pointer is over `LayoutSplitView3`): read only from the forms, it read as always under it.
        hoverSources = Set((nodes + schemaNodes).filter { $0.tag == "link" && $0["SourcePin"] == "IsActive" }
            .compactMap { $0["Source"] })
        for node in nodes + schemaNodes {
            let text = node.tag == "property" && node["name"] == "Expression" ? node["value"] : node["Expression"]
            if let text, names.expressions[text] == nil, let compiled = AIMPSkinExpression(text) { names.expressions[text] = compiled }
        }
        onLoaded = schemaNodes.first { $0.tag == "form" && $0["name"] == "AIMPMainForm" }?.properties["OnLoaded"]?["value"]
        let providerNodes = schema?.child("providers")?.children("provider") ?? []
        for node in providerNodes {
            if let name = node["name"], names.providers[name] == nil { names.providers[name] = AIMPProviderClass(node["class"]) }
        }
        for node in nodes + unopened.compactMap(\.form).flatMap({ $0.descendants() }) where node.tag == "item" {
            guard let name = node["name"] else { continue }
            let layout = AIMPSkinItem.Layout(node)
            // Its saved visibility is the first item's of the name, the one lookups find: an unopened
            // form's hidden namesake does not hide the main form's.
            if names.items.insert(name).inserted, !layout.savedShown { hiddenItems.insert(name) }
            // The forms shown first: a name an unopened form repeats is theirs.
            guard layout.isTabbedGroup, groups[name] == nil else { continue }
            // Only named pages are tabs: an unnamed one counts in neither `tabOf` nor the first shown.
            let pages = (node.child("items")?.children("item") ?? []).filter { $0["name"] != nil }
            let tabs = pages.compactMap { $0["name"] }
            groups[name] = tabs
            for (i, tab) in tabs.enumerated() where tabOf[tab] == nil { tabOf[tab] = (name, i) }
            initialPages[name] = pages.firstIndex { AIMPSkinItem.Layout($0).savedShown } ?? 0
        }
        // A page shows while it is its group's active one, whatever it was saved as.
        hiddenItems.subtract(tabOf.keys)
        var shownWith: [String: Set<String>] = [:]
        for node in nodes where node.tag == "item" {
            guard let name = node["name"], let tab = tabOf[name] else { continue }
            for link in node.properties["Bindings"]?.children("link") ?? []
            where link["TargetPin"] == "Visibility" && link["SourcePin"] == "Visibility" {
                if let source = link["Source"], let other = tabOf[source], other.group != tab.group {
                    shownWith[name, default: []].insert(source)
                }
            }
        }
        for (page, sources) in shownWith {
            for source in sources where shownWith[source]?.contains(page) == true { mirrors[page] = source }
        }
        names.groups = Set(groups.keys)
        for node in nodes where node.tag == "item" {
            guard let name = node["name"], AIMPSkinItem.Layout(node).isTabbedGroup else { continue }
            pageLinks[name] = node.properties["Bindings"]?.children("link").first { $0["TargetPin"] == "ActivePage" }
                .map { AIMPSkinLink($0, names: names) }
        }
        for node in providerNodes {
            guard let name = node["name"], providers[name] == nil else { continue }
            providers[name] = Provider(Self.fedByPlayback(node, name: name), names: names)
        }
        let sorted = providers.sorted { $0.key < $1.key }
        timers = sorted.filter { $0.value.kind == .timer }.map { ($0.key, $0.value) }
        visualizationHandlers = sorted.filter { $0.value.kind == .visualizationHandler }.map { ($0.key, $0.value) }
        for variable in schema?.child("variables")?.children("variable") ?? [] {
            guard let name = variable["name"]?.lowercased() else { continue }
            variables[name] = Variable(value: variable["value"] ?? "", isText: variable["valueType"] == "String")
        }
        for node in nodes where node.tag == "control" {
            for link in node.properties["Bindings"]?.children("link") ?? []
            where link["TargetPin"] == "Action" && link["SourcePin"] == "Position" {
                if let source = link["Source"], counterModule(source) != nil { selectorCounters.insert(source) }
            }
        }
        var fired = Set<String>(), readers = Set<String>()
        for node in nodes + schemaNodes where node.tag == "link" {
            guard let source = node["Source"] else { continue }
            let fires = node["TargetPin"] == "Action" || node["TargetPin"] == "ActionOnHold"
            if node["SourcePin"] == "Position", fires, node["Expression"] == nil { fired.insert(source) } else { readers.insert(source) }
        }
        commandCounters = fired.subtracting(readers)
        let menuNodes = providerNodes.filter { $0["class"] == "CustomContextMenu" && $0["name"] != nil }
        menuNames = Set(menuNodes.compactMap { $0["name"] })
        for entry in schema?.child("forms")?.children("form") ?? [] {
            guard let form = entry["name"], self.companions.contains(form) else { continue }
            for link in entry.properties["Bindings"]?.children("link") ?? []
            where link["TargetPin"] == "Visibility" && link["SourcePin"] == "Position" {
                guard let source = link["Source"], counterModule(source) != nil else { continue }
                windowCounters[source, default: []].append(WindowSwitch(form: form, link: AIMPSkinLink(link, names: names)))
            }
        }

        // The forms, read with the tables above, every control numbered.
        let tables = self
        var controls = 0
        func compile(_ node: AIMPNode) -> AIMPSkinControl {
            let id = AIMPSkinControl.ID(value: controls)
            controls += 1
            let held = (node.child("controls")?.children("control") ?? []).map(compile)
            return AIMPSkinControl(node, id: id, index: tables, controls: held)
        }
        func read(_ form: AIMPNode) -> AIMPSkinItem {
            AIMPSkinItem(form, compile: compile, names: names)
        }
        let mainForm = read(main)
        var named = Set<String>()
        let companionForms = companions.filter { named.insert($0.name).inserted }.compactMap { companion in
            forms[companion.name].map { (name: companion.name, form: read($0)) }
        }
        hold(main: mainForm, companions: companionForms, holders: sites.mapValues { read($0.holder) })
        for node in menuNodes {
            if let name = node["name"] { customMenus[name] = AIMPSkinCustomMenu(node, index: self) }
        }
        // What the forms NullPlayer does not open hold (M5's tray mini player, its lyrics window): a
        // key wired into one of them asks for what NullPlayer does not have. Not a tabbed group whose
        // pages the shown windows read: turning it changes what they show (AIMP Modern's visualizer
        // modes, kept in its hidden `QFI` form).
        for (name, form) in unopened {
            elsewhere.insert(name)
            elsewhere.formUnion(form?.descendants().compactMap { $0["name"] } ?? [])
        }
        let shownSources = Set(nodes.filter { $0.tag == "link" }.compactMap { $0["Source"] })
        for (group, pages) in groups where elsewhere.contains(group) && pages.contains(where: shownSources.contains) {
            elsewhere.subtract([group] + pages)
        }
    }

    /// Vega MP-120's tape counter, `CounterPosition`, is a counter bound to nothing that its script
    /// (`AnimatorIndexAndFindTrackNullPosition`) sets from the playback position. Until the script
    /// holds a position, the counter reads playback's through a `Position` link it is given here, so
    /// the dataflow reads it as any other bound counter.
    private static func fedByPlayback(_ node: AIMPNode, name: String) -> AIMPNode {
        guard name == "CounterPosition", node.properties["Bindings"] == nil else { return node }
        let link = AIMPNode.element("link", ["Source": "prvPlayerState", "SourcePin": "TrackPosition", "TargetPin": "Position"])
        let properties = node.children.first { $0.tag == "properties" }?.children ?? []
        return AIMPNode(tag: node.tag, attributes: node.attributes,
                        children: node.children.filter { $0.tag != "properties" } + [AIMPNode.propertyList(properties + [AIMPNode.bindings(link)])],
                        text: node.text)
    }

    /// Each sizable form's sizing. The main form says how near its edges a drag sizes it on its
    /// root item (Vega AIO), or on `Schema.xml`'s entry (RealPlayer 11); a skin's playlist and
    /// library windows on their `Schema.xml` entry; its deck's other windows keep their size. A
    /// form opens at its entry's `InitialSize` (Pandemic's and Red Bias's 920×640), a side given as
    /// 0 the natural one.
    private static func sizing(main: AIMPNode, companions: [AIMPSkin.Companion], schema: AIMPNode?) -> [String: Sizing] {
        let entries = schema?.child("forms")?.children("form") ?? []
        func entry(_ name: String) -> AIMPNode? { entries.first { $0["name"] == name } }
        func number(_ node: AIMPNode?, _ name: String) -> Double? {
            node?.properties[name]?.reference.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        }
        func made(_ edge: Double?, _ entry: AIMPNode?) -> Sizing? {
            guard let edge else { return nil }
            let asked = AIMPNode.numbers(entry?.properties["InitialSize"]?.reference)
            return Sizing(edge: CGFloat(edge), initialSize: asked.count == 2 ? CGSize(width: asked[0], height: asked[1]) : nil)
        }
        var sizing: [String: Sizing] = [:]
        let root = main.descendants().first { $0.tag == "item" }
        let mainEntry = entry("AIMPMainForm")
        // The root item's value is read as written: one that is not a number reads no sizing.
        let rootEdge = root?.properties["SizingHitTestAreaWidth"]?.reference ?? mainEntry?.properties["SizingHitTestAreaWidth"]?.reference
        sizing[""] = made(rootEdge.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }, mainEntry)
        for companion in companions where companion.role != .other {
            sizing[companion.name] = made(number(entry(companion.name), "SizingHitTestAreaWidth"), entry(companion.name))
        }
        return sizing
    }
}

extension AIMPSkinIndex.Provider {
init(_ node: AIMPNode, names: AIMPSkinIndex.Names) {
        let props = node.properties
        kind = AIMPProviderClass(node["class"])
        bindings = AIMPSkinBindings(node, names: names)
        script = props["Script"]?["value"]
        expression = props["Expression"]?["value"]
        template = props["Expression"]?.reference
        interval = Double(props["Interval"]?["value"] ?? "")
        module = props["Module"]?["value"].flatMap { Int($0) }
        positionDefault = props["PositionDefault"]?["value"].flatMap { Int($0) } ?? 0
    }
}
