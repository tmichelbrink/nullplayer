import Foundation

/// Binding sets a script holds as objects (`TASEBindings`): one it makes (`TASEBindings.Create`,
/// then `LinkAdd` and `Set('Source', …)`: Redly's font picker reads its text box this way), or a
/// control's own (`Control.Get('Bindings')`: Victor KD-D55's long press runs its key's
/// `ActionOnHold`). Their links are `AIMPSkinLink`s, read through the dataflow as the forms' are.
extension AIMPSkinScript {
    /// Which binding set: one the script made, or an object's own, by its name.
    enum BindingSetKey: Hashable {
        case made(Int)
        case own(String)
    }

    /// A binding set's links, each under an id of its own that a script's handle to it keeps
    /// whatever its `TargetPin` becomes. A pin finds the first link, in the order they were added,
    /// whose `TargetPin` it is.
    struct BindingSet {
        private(set) var links: [(id: Int, link: AIMPSkinLink)] = []
        private var nextID = 0

        init(_ links: [AIMPSkinLink] = []) {
            for link in links { add(link) }
        }

        subscript(id: Int) -> AIMPSkinLink? {
            get { links.first { $0.id == id }?.link }
            set {
                guard let at = links.firstIndex(where: { $0.id == id }) else { return }
                if let newValue { links[at].link = newValue } else { links.remove(at: at) }
            }
        }

        func id(ofPin pin: String) -> Int? { links.first { $0.link.target == pin }?.id }

        /// Every link gone; the ids go on from the last, so a handle to a cleared link finds nothing.
        mutating func removeAll() { links.removeAll() }

        @discardableResult
        mutating func add(_ link: AIMPSkinLink) -> Int {
            nextID += 1
            links.append((nextID, link))
            return nextID
        }
    }
}

extension AIMPSkinScript.Run {
    /// Nil when `member` is not a bindings method on `target`, so the host bridge carries on.
    func bindingsMethod(_ target: Value, _ member: Member, _ args: [Value]) throws -> Value? {
        let first = args.first?.string ?? ""
        switch (target, member) {
        case (.bindingsClass, .create):
            bindingSetsMade += 1
            let key = AIMPSkinScript.BindingSetKey.made(bindingSetsMade)
            bindingSets[key] = AIMPSkinScript.BindingSet()
            return .bindings(key)
        case (.object(let owner), .get) where args.count == 1 && first == "Bindings":
            return .bindings(ownBindings(owner))
        // A script frees what it made; nothing here holds on to it.
        case (_, .free):
            return Value.none
        // A new `TargetPin` moves the link to that pin, where `LinkFind` and the controls look; the
        // handle the script holds is the link's id, so it follows.
        case (.link(let set, let id), .set) where args.count == 2:
            guard let link = bindingSets[set]?[id] else { return Value.none }
            bindingSets[set]?[id] = Self.link(link, setting: first, to: args[1].string, names: skin.index.names)
            return Value.none
        case (.link(let set, let id), .get) where args.count == 1:
            return .string(bindingSets[set]?[id].flatMap { Self.attribute(first, of: $0) } ?? "")
        case (.bindings(let set), _):
            return try method(onSet: set, member, first)
        default:
            return nil
        }
    }

    private func method(onSet set: AIMPSkinScript.BindingSetKey, _ member: Member, _ pin: String) throws -> Value {
        let id = bindingSets[set]?.id(ofPin: pin), link = id.flatMap { bindingSets[set]?[$0] }
        switch member {
        // The pin's link when it has one, else a new one under it.
        case .linkAdd:
            if let id { return .link(set, id: id) }
            let made = bindingSets[set, default: AIMPSkinScript.BindingSet()]
                .add(Self.link(nil, setting: "TargetPin", to: pin, names: skin.index.names))
            return .link(set, id: made)
        case .linkFind:
            return id.map { .link(set, id: $0) } ?? Value.none
        case .linkDelete:
            if let id { bindingSets[set]?[id] = nil }
            return Value.none
        case .clear:
            bindingSets[set, default: AIMPSkinScript.BindingSet()].removeAll()
            return Value.none
        case .getDataAsText:
            return .string(link.map(text) ?? "")
        case .getDataAsNumber:
            return .number(link.map { flow.value(of: $0) } ?? 0)
        case .executeAction:
            if let link { try perform(link) }
            return Value.none
        default:
            throw Unsupported(what: "method \(member) on bindings")
        }
    }

    /// An object's own links (a control's, an item's, a provider's), loaded into a set of its name
    /// the first time.
    private func ownBindings(_ owner: HostObject) -> AIMPSkinScript.BindingSetKey {
        let key = AIMPSkinScript.BindingSetKey.own(owner.name)
        guard bindingSets[key] == nil else { return key }
        let bindings: AIMPSkinBindings?
        switch owner.element {
        case .control(let control): bindings = control.bindings
        case .item(let item): bindings = item.bindings
        case nil: bindings = owner.provider?.bindings
        }
        bindingSets[key] = AIMPSkinScript.BindingSet((bindings?.links ?? []).filter { $0.target != nil })
        return key
    }

    /// The link's source value as text: a file's tags through its `TextFormat`, a tabbed group's
    /// page by name, a text a script set, else the number.
    func text(of link: AIMPSkinLink) -> String {
        let source = link.source ?? "", pin = link.pin ?? ""
        if pin == "FileInfo" {
            return AIMPSkinTemplate.format(link.textFormat.flatMap { $0.isEmpty ? nil : $0 } ?? "%T", host: engine.host)
        }
        if pin == "ActivePage", let pages = skin.index.groups[source], !pages.isEmpty { return pages[flow.activePage(source)] }
        if let text = engine.state.script[source].text { return text }
        return Value.number(flow.value(of: link)).string
    }

    /// A link to `source`'s `pin` (`BindingsGetDataAsText3`), with its `Expression` when it has one.
    func link(source: String, pin: String, expression: String, textFormat: String) -> AIMPSkinLink {
        AIMPSkinLink(source: source, pin: pin, target: nil, expression: expression.isEmpty ? nil : expression, textFormat: textFormat,
                     names: skin.index.names)
    }

    /// What pressing a control bound so does: an AIMP action, a counter stepped by the link's
    /// `Expression`, a tabbed group's page, or an item shown or hidden.
    private func perform(_ link: AIMPSkinLink) throws {
        let source = link.source ?? "", pin = link.pin ?? ""
        if let action = AIMPAction(source) {
            engine.ask(.action(action))
        } else if pin == "ActivePage", skin.index.groups[source] != nil {
            engine.state.script[source].activePage = AIMPSkinScript.integer(flow.value(of: link))
            // A mirrored page's group turns with it, as on a click (`AIMPSkinRuntime.turnPage`).
            let index = skin.index, page = flow.activePage(source)
            if let pages = index.groups[source], pages.indices.contains(page), let mirror = index.mirrors[pages[page]],
               let other = index.tabOf[mirror] {
                engine.state.script[other.group].activePage = other.index
            }
        } else if pin == "Visible" || pin == "Visibility" {
            engine.state.override(visible: flow.value(source, pin) == 0, of: source, gateFrom: flow)
        } else if pin == "Position", skin.index.providers[source]?.kind.isCounter == true {
            // As a script's own move: a counter stopped by a limit passes it on, so this run is
            // undone with it and both run again, rather than the move being lost.
            try engine.movingCounter(source, to: flow.wrapped(AIMPSkinScript.integer(flow.value(of: link)), counter: source))
        }
    }

    // MARK: - A link's attributes

    /// The attributes a link object answers `Get` and `Set` for, as AIMP names them.
    private static func attribute(_ name: String, of link: AIMPSkinLink) -> String? {
        switch name {
        case "Source": return link.source
        case "SourcePin": return link.pin
        case "TargetPin": return link.target
        case "Expression": return link.expression
        case "TextFormat": return link.textFormat
        default: return nil
        }
    }

    /// `link` (a new one for nil) with `attribute` set to `value`, read again so its expression is
    /// compiled. An attribute a link does not have is dropped.
    private static func link(_ link: AIMPSkinLink?, setting attribute: String, to value: String,
                             names index: AIMPSkinIndex.Names) -> AIMPSkinLink {
        let given = { (name: String) in name == attribute ? value : link.flatMap { Self.attribute(name, of: $0) } }
        return AIMPSkinLink(source: given("Source"), pin: given("SourcePin"), target: given("TargetPin"),
                            expression: given("Expression"), textFormat: given("TextFormat"), names: index)
    }
}
