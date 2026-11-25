/// One `Bindings/link`: the pin `target` of a control, item or provider reads `source`'s `pin`,
/// shaped by the link's `Expression` (`reference/layout.md` § *Visibility*). Read once as the skin
/// loads: what it reads resolved (`read`), the expression compiled.
struct AIMPSkinLink: Sendable {
    let source: String?
    let pin: String?
    let target: String?
    /// `source`'s `pin`, resolved against the skin's names.
    let read: AIMPSkinSource
    /// The `Expression` as written, and compiled; nil when the link has none or it does not parse,
    /// and the link passes its source's value on as it is.
    let expression: String?
    let shape: AIMPSkinExpression?
    /// What a `FileInfo` link shows of the track (`%Title`), or a hint's label.
    let textFormat: String?

    init(source: String?, pin: String?, target: String?, expression: String? = nil, textFormat: String? = nil,
         names: AIMPSkinIndex.Names) {
        (self.source, self.pin, self.target, self.expression, self.textFormat) = (source, pin, target, expression, textFormat)
        read = AIMPSkinSource(source ?? "", pin ?? "", names: names)
        shape = expression.flatMap { names.expressions[$0] ?? AIMPSkinExpression($0) }
    }

    /// `value` as the link's `Expression` shapes it.
    func shaped(_ value: Double) -> Double { shape?.evaluate(value: value) ?? value }
}

/// An element's `Bindings`: its links in document order, and by the pin they feed.
struct AIMPSkinBindings: Sendable {
    /// Whether the node has a `Bindings` property at all, even an empty one (a label with none is
    /// as wide as its text: `AIMPSkinLayout.autoSized`).
    let declared: Bool
    let links: [AIMPSkinLink]
    private let byTarget: [String: [AIMPSkinLink]]

    /// `declared`: whether the skin gave a `Bindings` property at all.
    init(links: [AIMPSkinLink], declared: Bool = true) {
        self.declared = declared
        self.links = links
        byTarget = Dictionary(grouping: links.filter { $0.target != nil }, by: { $0.target! })
    }

    /// The first link to `target`.
    subscript(target: String) -> AIMPSkinLink? { byTarget[target]?.first }

    /// Every link to `target`, in document order.
    func all(_ target: String) -> [AIMPSkinLink] { byTarget[target] ?? [] }
}
