import Foundation

/// Where a skin family keeps, per skin, the windows of its own the user arranged: each window's
/// top-left, which ones were open when the session ended, and whether each was shown or hidden.
///
/// A skin's own windows have no other home: the player's position is the main-window restore path's,
/// and NullPlayer's windows are `AppStateManager`'s. Restored on the rule `.wal` follows: **what the
/// user last decided wins over what the skin declares**. Every key is the family's prefix plus a
/// fixed suffix, so `.wmz`'s are `wmpViewOrigins` and `wmpOpenViews`, as they always were.
struct SkinWindowStore {
    let defaults: UserDefaults
    /// The family's key prefix (`wmp`).
    let family: String

    private var originsKey: String { family + "ViewOrigins" }
    private var openWindowsKey: String { family + "OpenViews" }
    private var visibilityKey: String { family + "WindowVisibility" }

    /// The window's top-left in screen coordinates.
    func origin(skin: String, window: String) -> CGPoint? {
        guard let values = defaults.dictionary(forKey: originsKey)?[Self.windowKey(skin, window)] as? [Double],
              values.count == 2, values[0].isFinite, values[1].isFinite else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    func setOrigin(_ origin: CGPoint, skin: String, window: String) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        var values = defaults.dictionary(forKey: originsKey) ?? [:]
        values[Self.windowKey(skin, window)] = [Double(origin.x), Double(origin.y)]
        defaults.set(values, forKey: originsKey)
    }

    /// The windows this skin had open when the session ended, in the order they were opened. The
    /// player's own is not one of them.
    func openWindows(skin: String) -> [String] {
        defaults.dictionary(forKey: openWindowsKey)?[Self.skinKey(skin)] as? [String] ?? []
    }

    func setOpenWindows(_ windows: [String], skin: String) {
        var values = defaults.dictionary(forKey: openWindowsKey) ?? [:]
        if windows.isEmpty { values.removeValue(forKey: Self.skinKey(skin)) }
        else { values[Self.skinKey(skin)] = windows }
        defaults.set(values, forKey: openWindowsKey)
    }

    /// Whether each window was last shown or hidden, keyed by its lowercased name. A window with no
    /// entry has never been recorded, which is not the same as closed: its skin's own default applies.
    func visibility(skin: String) -> [String: Bool] {
        defaults.dictionary(forKey: visibilityKey)?[Self.skinKey(skin)] as? [String: Bool] ?? [:]
    }

    func setVisibility(_ visible: Bool, window: String, skin: String) {
        var values = defaults.dictionary(forKey: visibilityKey) ?? [:]
        var skinValues = values[Self.skinKey(skin)] as? [String: Bool] ?? [:]
        skinValues[window.lowercased()] = visible
        values[Self.skinKey(skin)] = skinValues
        defaults.set(values, forKey: visibilityKey)
    }

    /// A skin's identity in every per-skin key, length-prefixed so two names that differ only by case
    /// or by a separator cannot collide. Also what `HostedWindowBorderLayout` stores a hosted window's
    /// interior under, so both halves of a skin's geometry agree on who it belongs to.
    static func skinKey(_ skin: String) -> String {
        "\(skin.utf8.count):\(skin.lowercased())"
    }

    /// One window of one skin.
    static func windowKey(_ skin: String, _ window: String) -> String {
        "\(skinKey(skin))|\(window.lowercased())"
    }
}
