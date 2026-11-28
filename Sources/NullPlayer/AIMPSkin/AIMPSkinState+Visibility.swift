import Foundation

extension AIMPSkinDataflow {
    /// What `name`'s `Visibility` bindings say now (1 shown, 0 hidden), its mirror's `Visibility`
    /// link left out as drawing leaves it (`isMirror`), any other link to the mirror kept; nil with
    /// none. An override of its `Visible` holds until this changes (`Engine.pushVisibility`).
    func visibilityGate(_ name: String) -> Double? {
        gatesOpen(skin.index.byName[name]?.gates ?? [], of: name).map { $0 ? 1 : 0 }
    }
}

extension AIMPSkinState {
    /// Shows or hides `name` over its `Visibility` bindings, as a script, a close or a menu does.
    /// Taken afresh (no override standing), the gate is recorded as it stands now, so the override
    /// holds until the bindings next change from here: not from a value seen under an earlier
    /// override (Vega MP-120 swaps its stop key on every stop), nor from one missed while none stood.
    mutating func override(visible: Bool, of name: String, gateFrom flow: AIMPSkinDataflow) {
        if script[name].visible == nil { script[name].visibleGate = flow.visibilityGate(name) }
        script[name].visible = visible
    }
}
