import Foundation

/// A menu the skin builds itself (`CustomContextMenu` in `Schema.xml`): AIMP Modern v3.63's menu bar,
/// File, Play, Options, View and Help, each a key whose `PopupMenu` names one. An item is a caption
/// (`@Lng:` strings filled in) and the bindings a key would have: its `Action` does what the same
/// binding on a key does (`AIMPSkinControl.Input.press`), its `State` ticks it; an item holding items
/// is a submenu, a `-` caption a separator.
struct AIMPSkinCustomMenu: Sendable {
    struct Item: Sendable {
        let caption: String
        /// What choosing it does; nil for none (a submenu's own line, a separator).
        let press: AIMPSkinTarget.Kind?
        /// What ticks it, read when the menu opens.
        let state: AIMPSkinLink?
        let items: [Item]

        var isSeparator: Bool { caption == "-" }
        /// An AIMP action NullPlayer does not do (`AIMPAction.isHandled`), a popup it has nothing like
        /// (`AIMPSkinPopup.unavailable`), or handlers run only as a key goes down and comes up, which a
        /// menu choice has no press for: shown, but not available.
        var isUnavailable: Bool {
            switch press {
            case .action(let action)?: return !action.isHandled
            case .menu(.unavailable?)?, .hold(_, _)?: return true
            default: return false
            }
        }
    }

    let items: [Item]

    /// The menu provider `name`; nil when the skin declares none of that name.
    init?(_ name: String, index: AIMPSkinIndex) {
        guard let node = index.customMenus[name] else { return nil }
        items = Self.items(node, index: index)
    }

    private static func items(_ node: AIMPNode, index: AIMPSkinIndex) -> [Item] {
        (node.child("items")?.children("item") ?? []).map { item in
            let props = item.properties
            let bindings = AIMPSkinBindings(item, names: index.names)
            return Item(caption: AIMPSkinLanguage.expanded(props["Caption"]?.reference ?? "", strings: index.strings),
                        press: AIMPSkinControl.Input.press(bindings, props: props, index: index),
                        state: bindings["State"],
                        items: items(item, index: index))
        }
    }
}
