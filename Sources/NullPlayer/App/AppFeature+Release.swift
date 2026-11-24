import Foundation

extension AppFeature {
    /// Whether release builds offer the feature yet. A skin family still in development is in debug
    /// builds only until it is ready to ship (AIMP skins; Audion faces were, until they shipped).
    /// Kept apart from `AppCapabilities`, which says only what an edition supports.
    var isReleased: Bool {
        #if DEBUG
        return true
        #else
        return self != .aimpSkinMode
        #endif
    }

    /// Whether this build offers the feature: released, and supported by its edition.
    var isOffered: Bool { isReleased && AppCapabilities.supports(self) }
}
