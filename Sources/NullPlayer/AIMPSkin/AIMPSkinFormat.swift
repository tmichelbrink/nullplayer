import Foundation

/// Sizes and lengths as AIMP 5.40 writes them, for its templates, its playlist and its displays.
enum AIMPSkinFormat {
    /// A size in bytes: two decimals in the largest unit under it ("344.61 KB", "5.05 MB"), and whole
    /// bytes below a kilobyte ("0 B" for an empty playlist).
    static func size(_ bytes: Double) -> String {
        guard bytes >= 1024 else { return "\(AIMPSkinScript.integer(max(0, bytes))) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = bytes / 1024, unit = 0
        while value >= 1024, unit < units.count - 1 { value /= 1024; unit += 1 }
        return String(format: "%.2f %@", value, units[unit])
    }

    /// `m:ss`, the minutes uncapped.
    static func minutes(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// `h:mm:ss`.
    static func hours(_ seconds: Int) -> String { String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }

    /// `h:mm:ss` from an hour, else `m:ss`.
    static func length(_ seconds: Int) -> String { seconds >= 3_600 ? hours(seconds) : minutes(seconds) }
}
