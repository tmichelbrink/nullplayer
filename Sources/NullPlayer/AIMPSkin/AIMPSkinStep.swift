import CoreGraphics
import Foundation

/// What a click, or a wheel notch, does to a skin counter's position or a tabbed group's page: the
/// skin's `Expression` over the current one (`Value`), compiled once and sorted by what the wheel
/// does with it.
struct AIMPSkinStep: Equatable, Sendable {
    /// Nil for none, or one that does not parse: a click leaves the position where it is.
    let expression: AIMPSkinExpression?
    let wheel: Wheel

    enum Wheel: Equatable, Sendable {
        /// Takes no notches: the expression picks a position, or there is none.
        case none
        /// One position a notch, stopping at the ends; a click steps to the next, however the skin
        /// spells it (`Value + 1`, `(value+1)mod 3`, `(Value + 1) MOD 6`). Akai CS-F33's TAPE
        /// SELECTOR, Pioneer's TAPE switch.
        case next
        /// The notches are the expression's `ScrollDelta` (`Value + ScrollDelta`: Denon DR-F8's
        /// MONITOR); a click is one.
        case scrollDelta
    }

    init(_ text: String?) {
        expression = text.flatMap(AIMPSkinExpression.init)
        if expression?.reads("scrolldelta") == true {
            wheel = .scrollDelta
        } else if expression?.stepsToNext == true {
            wheel = .next
        } else {
            wheel = .none
        }
    }

    /// The fixed position the expression names (`3`): what a right-click's `ContextMenu` sets.
    var position: Int? { expression?.constant.flatMap { Int(exactly: $0) } }

    /// Where a click, or `notches` of the wheel, takes `current`; nil where the expression gives
    /// nothing (none, one that does not evaluate, or a number no `Int` position holds), and the
    /// position stays.
    func next(from current: Double, notches: Int = 1) -> Double? {
        var variables = ["value": current]
        if wheel == .scrollDelta { variables["scrolldelta"] = Double(notches) }
        guard let next = expression?.evaluate(variables: variables), Int(exactly: next.rounded(.towardZero)) != nil else { return nil }
        return next
    }
}
