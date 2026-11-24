import AppKit

/// Files, folders or cue sheets dropped on a window that plays them: whether a drop holds
/// any, and the tracks it stands for. What a window then does with the tracks (append and play,
/// replace the queue) is its own.
enum PlaylistDrop {
    /// The cursor a drag over a window that plays drops shows: a copy only for something playable.
    static func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        accepts(urls(in: sender)) ? .copy : []
    }

    /// The file URLs a drag carries.
    static func urls(in sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Whether a drop holds anything playable: media, folders, cue sheets.
    private static func accepts(_ urls: [URL]) -> Bool {
        urls.contains { $0.pathExtension.lowercased() == "cue" } || LocalFileDiscovery.hasSupportedDropContent(urls, includeVideo: true)
    }

    /// The tracks the drop names itself: each cue sheet's, and each audio file's (one with a cue sheet
    /// beside it, the sheet's), each sheet once, so a `.cue` and its audio dropped together add the
    /// album once. Reads the files on the caller's thread (`gather` calls it off the main thread).
    static func namedTracks(_ urls: [URL]) -> [Track] {
        var tracks: [Track] = []
        var cueSources = Set<String>()
        func appendCue(_ expanded: [Track]) {
            guard !expanded.isEmpty else { return }
            if let source = expanded.first?.cueSourceURL?.standardizedFileURL.path, !cueSources.insert(source).inserted { return }
            tracks.append(contentsOf: expanded)
        }
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "cue" {
                if let expanded = AudioEngine.tracksForCueOrSibling(url: url) { appendCue(expanded) }
            } else if AudioFileValidator.supportedExtensions.contains(ext) {
                if let expanded = AudioEngine.tracksForCueOrSibling(url: url), !expanded.isEmpty {
                    appendCue(expanded)
                } else {
                    tracks.append(Track(url: url))
                }
            }
        }
        return tracks
    }

    /// Takes a drop: false when it holds nothing playable. True means the drop was taken, not that it
    /// yields tracks: the tracks it names itself (`namedTracks`, its cue sheets read off the main
    /// thread), then the media found in its other items, folders searched off the main thread too,
    /// without the ones it named already. Call it on the main thread, as a drop arrives: `deliver`
    /// runs there once, after this returns, with no tracks when the search found none; a drop of cue
    /// sheets alone is not delivered when they name no tracks.
    static func gather(_ urls: [URL], deliver: @escaping ([Track]) -> Void) -> Bool {
        guard accepts(urls) else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            let named = namedTracks(urls)
            DispatchQueue.main.async { complete(urls, named: named, deliver: deliver) }
        }
        return true
    }

    /// The tracks a drop names itself, then the media its other items hold, without the ones named.
    private static func complete(_ urls: [URL], named: [Track], deliver: @escaping ([Track]) -> Void) {
        let others = urls.filter { $0.pathExtension.lowercased() != "cue" }
        guard !others.isEmpty else {
            if !named.isEmpty { deliver(named) }
            return
        }
        LocalFileDiscovery.discoverMediaURLsAsync(from: others, includeVideo: true) { found in
            let taken = Set(named.map(\.url))
            deliver(named + found.filter { !taken.contains($0) }.map { Track(url: $0) })
        }
    }
}
