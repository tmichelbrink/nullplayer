import CoreGraphics
import Foundation

/// A `control` of a form, read once as the skin loads (`AIMPSkinIndex`): its class with what that
/// class alone reads (`AIMPControlClass`), its bindings by the pin they feed, where it sits, how its
/// picture and text draw, and what pressing it does. The layout, the dataflow and the scripts read
/// these rather than the node's properties; a control a script restyled
/// (`AIMPSkinState.Object.properties`) is read again with the script's values over its own
/// (`restyled`). `reference/layout.md` § Controls has the rules.
final class AIMPSkinControl: AIMPSkinElement, Sendable {
    /// Which control it is, for the skin's life (a restyled control keeps it): the window keys what
    /// the pointer is over and holds, and the gauges it eases, by it, not by name: a name may be
    /// missing or shared, and two controls with one name lit and released as one.
    struct ID: Hashable, Sendable {
        let value: Int

        /// A visualization screen's VU needle `channel` (0 left, 1 right), eased like a gauge
        /// (`AIMPSkinGauges`) under an id no control has.
        func meter(_ channel: Int) -> ID { ID(value: -(value * 2 + channel + 1)) }
    }

    let id: ID
    let name: String?
    /// Its `class` (`StateDisplay`, `Button`), and its `Tag` and `PlaceInfo` margins as the skin
    /// wrote them, which a script reads (`AIMPSkinIndex.Element`).
    let className: String?
    let tag: String?
    let writtenMargins: [Double]
    /// The name a script restyles it by: its name, else its `link` (`<control link="Playlist">`).
    let styleKey: String?
    let kind: AIMPControlClass
    let bindings: AIMPSkinBindings
    let gates: [AIMPSkinLink]
    let savedShown: Bool
    /// `PlaceInfo`; a control without one does not show.
    let placement: AIMPPlacement.Info?
    /// The controls it holds, placed in its rect (Cassette-3D's `Panel` of animators).
    let controls: [AIMPSkinControl]

    // MARK: Picture

    /// Its `Skin`: the picture, a filmstrip of frames.
    let picture: String?
    /// The frame that is its mask (`MaskFrame`, on its `Skin` or on the resource that names; `-1`
    /// is none: Red Bias 2.0's visualization, which clipped to its logo).
    let maskFrame: Int?
    /// `BlendingModeOpacity` below 255, and `BlendingMode` as Core Graphics draws it.
    let opacity: Double?
    let blend: CGBlendMode?
    /// Mirrored (Akai GX-R60's right reel: the left's strip, flipped and run backwards).
    let flipX: Bool
    let flipY: Bool

    /// What its caption or display shows, and in what font.
    let text: Text
    let input: Input

    /// The skin's own markup for it, which a script's restyle is read again over (`restyled`); nil
    /// for a control read from a format scripts do not restyle.
    let markup: Markup?
    /// Shown and clicked only within its item, though its format's controls belong to the window
    /// (`AIMPSkinDialect.controlsOutliveItems`): AIMP's own tab strip and list, which an AIMP 3.0 or
    /// AIMP 2 reader stands in for, live inside their site (Vega AIO's tab row, 2 px tall in its
    /// compact window, shows no tab).
    let confined: Bool

    init(id: ID, name: String?, className: String?, styleKey: String?, kind: AIMPControlClass, bindings: AIMPSkinBindings,
         savedShown: Bool = true, placement: AIMPPlacement.Info?, controls: [AIMPSkinControl] = [],
         picture: String?, maskFrame: Int? = nil, opacity: Double? = nil, blend: CGBlendMode? = nil,
         flipX: Bool = false, flipY: Bool = false, text: Text, input: Input,
         tag: String? = nil, writtenMargins: [Double] = [], markup: Markup? = nil, confined: Bool = false) {
        self.id = id
        self.name = name
        self.className = className
        self.styleKey = styleKey
        self.kind = kind
        self.bindings = bindings
        gates = bindings.all("Visibility")
        self.savedShown = savedShown
        self.placement = placement
        self.controls = controls
        self.picture = picture
        self.maskFrame = maskFrame
        self.opacity = opacity
        self.blend = blend
        self.flipX = flipX
        self.flipY = flipY
        self.text = text
        self.input = input
        self.tag = tag
        self.writtenMargins = writtenMargins
        self.markup = markup
        self.confined = confined
    }

    /// An animator's settings; nil for any other control.
    var animator: AIMPControlClass.Animator? {
        if case .animator(let animator) = kind { animator } else { nil }
    }

    /// AIMP's `BlendingMode` as Core Graphics draws it; nil for `bmNormal` and anything unknown.
    static func blendMode(_ name: String?) -> CGBlendMode? {
        switch name {
        case "bmScreen": return .screen
        // What is under it, its colour taken out by the grey it draws (M5's gray art over its cover).
        case "bmGrayscale": return .saturation
        case "bmDifference": return .difference
        case "bmMultiply": return .multiply
        case "bmAdd", "bmAdditive", "bmAddition": return .plusLighter
        case "bmLighten": return .lighten
        case "bmDarken": return .darken
        case "bmOverlay": return .overlay
        case "bmExclusion": return .exclusion
        case "bmSoftLight": return .softLight
        case "bmHardLight": return .hardLight
        default: return nil
        }
    }
}

extension AIMPPlacement {
    /// A control's `PlaceInfo`: `anchors` and `margins` (left, top, right, bottom) and a `Size`.
    struct Info: Sendable {
        let anchors: [Int]
        let margins: [Int]
        /// Nil when it is not two numbers: the control then has no room.
        let size: CGSize?

        /// Where it sits in `parent`, with the margins a script `moved` (0 left … 3 bottom).
        func rect(in parent: CGRect, moved: [Int: Double] = [:]) -> CGRect {
            var margins = margins
            for (side, value) in moved where margins.indices.contains(side) {
                // One no layout holds (NaN, infinity, past a million, as `AIMPNode.numbers` has it)
                // leaves the margin the skin gave.
                guard let whole = Int(exactly: value.rounded()), (-1_000_000...1_000_000).contains(whole) else { continue }
                margins[side] = whole
            }
            guard let size else { return .zero }
            return AIMPPlacement.rect(anchors: anchors, margins: margins, size: size, in: parent) ?? .zero
        }
    }
}
