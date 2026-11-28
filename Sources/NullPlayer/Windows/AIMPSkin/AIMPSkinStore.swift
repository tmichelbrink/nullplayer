import AppKit

/// What AIMP mode keeps of each installed skin, by its file name through `SkinWindowStore.skinKey`
/// (never the name a skin embeds, which may be empty or shared by two skins): where each form window
/// was left (`SkinWindowStore`, as `.wmz` keeps its views'), whether each form other than the playlist
/// and library was last shown, the size the user gave a sizable form, and the visualization screen's
/// mode. Restored on the rule `.wal` follows: what the user last decided wins over what the skin declares.
struct AIMPSkinStore {
    let defaults: UserDefaults

    /// One installed skin's records; `name` is its file name without the extension.
    func skin(_ name: String) -> Skin { Skin(defaults: defaults, name: name) }

    struct Skin {
        let defaults: UserDefaults
        let name: String

        private var windows: SkinWindowStore { SkinWindowStore(defaults: defaults, keys: .aimp) }

        /// The form window's top-left in screen coordinates, where the user last left it.
        func origin(window: String) -> CGPoint? { windows.origin(skin: name, window: window) }

        func setOrigin(_ origin: CGPoint, window: String) { windows.setOrigin(origin, skin: name, window: window) }

        /// Whether each form was last shown or hidden, keyed by its lowercased name. A form with no
        /// entry has never been recorded, which is not the same as closed: the skin's own default applies.
        var visibility: [String: Bool] { record(Keys.visibility, SkinWindowStore.skinKey(name)) ?? [:] }

        func setVisibility(_ visible: Bool, window: String) {
            var values = visibility
            values[window.lowercased()] = visible
            setRecord(values, Keys.visibility, SkinWindowStore.skinKey(name))
        }

        /// The size the user last gave form `form` (nil: the main form), in skin pixels.
        func size(form: String?) -> CGSize? {
            (record(Keys.sizes, SkinWindowStore.windowKey(name, form ?? "")) as String?).map(NSSizeFromString)
                .flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        }

        func setSize(_ size: CGSize, form: String?) {
            setRecord(NSStringFromSize(size), Keys.sizes, SkinWindowStore.windowKey(name, form ?? ""))
        }

        /// The visualization screen's mode last chosen (`acVisualNext` / `acVisualPrev`).
        var visualMode: AIMPVisualMode? {
            (record(Keys.visualModes, SkinWindowStore.skinKey(name)) as String?).flatMap(AIMPVisualMode.init(rawValue:))
        }

        func setVisualMode(_ mode: AIMPVisualMode) { setRecord(mode.rawValue, Keys.visualModes, SkinWindowStore.skinKey(name)) }

        private func record<Value>(_ key: String, _ id: String) -> Value? {
            defaults.dictionary(forKey: key)?[id] as? Value
        }

        private func setRecord(_ value: Any, _ key: String, _ id: String) {
            var values = defaults.dictionary(forKey: key) ?? [:]
            values[id] = value
            defaults.set(values, forKey: key)
        }
    }

    /// The defaults keys, one dictionary each, by skin (or by skin and form).
    private enum Keys {
        static let visibility = "aimpWindowVisibility"
        static let sizes = "aimpSkinSizes"
        static let visualModes = "aimpVisualModes"
    }
}

extension SkinWindowStore.Keys {
    /// AIMP's form-window origins, beside `.wmz`'s. Which forms show is `AIMPSkinStore`'s
    /// visibility record, so the open-windows key is never written.
    static let aimp = Self(origins: "aimpViewOrigins", openWindows: "aimpOpenViews")
}
