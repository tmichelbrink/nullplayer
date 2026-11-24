import Foundation

/// Answers what a binding reads: `source`'s `pin`, from the form (a tabbed group's page, an item's
/// visibility), the player (`AIMPSkinHostState.pin`), or `Schema.xml`'s providers, the skin's own
/// dataflow (`reference/layout.md` § *Providers*):
/// - `LogicalOperatorCommutator`: `Result` is its `Expression` over `value1…valueN`, each a link
///   (with none, `value1`);
/// - `LogicalOperatorCounter` / `ScriptableOperatorCounter`: `Position` is the skin state's, else a
///   bound `Position` link, else `PositionDefault`.
/// Anything else, and anything a script would set, reads 0. What a frame makes of a control from
/// these is `AIMPSkinDataflow+Controls.swift`.
struct AIMPSkinDataflow {
    let skin: AIMPSkin
    let host: AIMPSkinHostState
    let state: AIMPSkinState
    /// Each commutator's value, worked out once for this state at each depth it is read from: one
    /// that reads others through shared inputs would otherwise be read again on every path to it,
    /// exponentially many in a crafted skin.
    private let commutators = Memo()

    private final class Memo {
        var values: [String: Double] = [:]
    }

    /// Whether a form or item is shown: its `Visible` pin.
    func isVisible(_ name: String, depth: Int = 0) -> Bool { value(name, "Visible", depth: depth) != 0 }

    /// Whether `form` is in its dock site now; a form no site holds never is.
    func isDocked(_ form: String) -> Bool {
        // A form with no site to dock into keeps its own window, whatever a script asked: AIMP Modern
        // v3.63 docks its library, which has none, and hid the library window's caption.
        guard let site = skin.index.siteOf[form] else { return false }
        return state.script[form].docked ?? skin.index.sites[site]?.initiallyDocked ?? false
    }

    /// The item `name` sits in now.
    func parent(of name: String) -> String? { state.script[name].parent ?? skin.index.parentOf[name] }

    /// `value` as provider `name` holds it: wrapped by its `Module`, when it has one. A `Module` of 1
    /// holds it at 0, as AIMP does; `AIMPSkinIndex.counterModule`, the positions a control can show, has none then.
    func wrapped(_ value: Int, counter name: String) -> Int {
        guard let module = skin.index.providers[name]?.module, module > 0 else { return value }
        let remainder = value % module
        return remainder < 0 ? remainder + module : remainder
    }

    /// The page a group shows: what its `ActivePage` binding reads, else what a key or script
    /// turned it to, else the first.
    func activePage(_ group: String, depth: Int = 0) -> Int {
        let count = skin.index.groups[group]?.count ?? 0
        // Two groups that each take the other's page keep each other in step; neither is the
        // other's source, so each turns by its pages' own bindings: Kantaris-Teyp's left and right
        // speakers (`GroupLSp`, `GroupRSp`), each page shown with its style's page of `QFI`, read
        // as page 0 whatever the style.
        let link = skin.index.pageLinks[group].flatMap { link -> AIMPSkinLink? in
            if case .page(let other) = link.read, case .page(group)? = skin.index.pageLinks[other]?.read { return nil }
            return link
        }
        // A reading no `Int` holds (an expression's infinity) binds nothing.
        let bound = link.flatMap { Int(exactly: value(of: $0, depth: depth + 1).rounded()) }
        return count == 0 ? 0 : min(max(bound ?? state.script[group].activePage ?? shownPage(group, depth: depth) ?? skin.index.initialPages[group] ?? 0, 0), count - 1)
    }

    /// The first of a group's pages whose own `Visibility` bindings are all on, when some are off:
    /// showing a page turns its group to it (M5's two transport rows, one shown for each value of
    /// `modernplaybtn`). A mirrored page's binding is a push, not a condition (`AIMPSkinIndex.mirrors`).
    private func shownPage(_ group: String, depth: Int) -> Int? {
        guard depth < 16, let pages = skin.index.pageGates[group] else { return nil }
        return pages.firstIndex { gates in gates.allSatisfy { value(of: $0, depth: depth + 1) != 0 } }
    }

    /// An item's visibility (`value(.item)`).
    private func itemValue(_ name: String, depth: Int) -> Double {
        if state.script[name].autoHidden { return 0 }
        // A dock site shows only while it holds its form, docked and shown, as the layout draws
        // it: Telos's `DockingState` counter watches its sites' `Visibility` to re-arrange its
        // columns when the playlist opens or closes.
        if let site = skin.index.sites[name], !(isDocked(site.form) && isVisible(site.form, depth: depth + 1)) { return 0 }
        if let set = state.script[name].visible { return set ? 1 : 0 }
        // An item's own `Visibility` bindings, as the painter shows it (Unsquareable's tab column
        // shows while `TabControl_Small`, shown with the hidden compact player, is hidden).
        // An item saved hidden (`InitialVisible` False) stays so whatever its bindings read, as AIMP
        // 5.40 opens Black & White, Metro Color and AIMPify: showing it (as a binding reading true
        // would suggest) drew their hidden mini player and second tab strip.
        let gates = (skin.index.byName[name]?.gates ?? []).filter { !isMirror($0, of: name) }
        if !gates.isEmpty, !gates.allSatisfy({ value(of: $0, depth: depth + 1) != 0 }) { return 0 }
        return (!skin.index.hiddenItems.contains(name) && isOnActivePage(name, depth: depth + 1)) ? 1 : 0
    }

    /// Whether `item` is its group's active page. Only its own group counts: Revox B-710 keeps its
    /// counter and meter modes (`TimeMode`, `Level`) as tabbed groups on a hidden page of an outer
    /// group, and their pages still read visible. Hidden-outright items are the layout's business.
    func isOnActivePage(_ item: String, depth: Int = 0) -> Bool {
        guard let tab = skin.index.tabOf[item] else { return true }
        return activePage(tab.group, depth: depth) == tab.index
    }

    /// Whether `gate` is `item`'s binding to its mirrored page (`AIMPSkinIndex.mirrors`): a push
    /// the pages' turning carries out, not a condition.
    func isMirror(_ gate: AIMPSkinLink, of item: String?) -> Bool {
        guard let item, let mirror = skin.index.mirrors[item] else { return false }
        return gate.source == mirror && gate.pin == "Visibility"
    }

    /// One link's value: what it reads, shaped by the link's own `Expression`.
    func value(of link: AIMPSkinLink, depth: Int = 0) -> Double {
        link.shaped(value(link.read, depth: depth))
    }

    /// What `link` reads, as a trigger watches it: a concatenator's inputs, and theirs (its text
    /// changes when any of them does), else its value. A `FileInfo` input's text moves while its
    /// number stays (a new title under `%T`), so every field of the playing track a template can show
    /// counts too, by their hash (not the formatted text: this is read every settle pass of every
    /// frame).
    func inputs(of link: AIMPSkinLink, depth: Int = 0) -> [Double] {
        guard case .concatenator(let name) = link.read, depth < 8 else { return [value(of: link)] }
        return (skin.index.providers[name]?.bindings.links ?? []).flatMap { input -> [Double] in
            let numbers = inputs(of: input, depth: depth + 1)
            guard input.pin == "FileInfo" else { return numbers }
            let track = host.player
            var hasher = Hasher()
            for text in [track.title, track.artist, track.album, track.genre, track.fileType, track.fileName, track.fileDirectory] {
                hasher.combine(text)
            }
            for number in [track.year, track.bitrate, track.sampleRate, track.channels, track.durationSeconds, track.discNumber] {
                hasher.combine(number)
            }
            hasher.combine(track.fileSize)
            hasher.combine(track.rating)
            hasher.combine(track.playCount)
            return numbers + [Double(hasher.finalize())]
        }
    }

    /// `source`'s `pin`, named at run time (a script's `BindingsGetDataAsInteger`, a counter's
    /// `Position`), resolved as a link's is.
    func value(_ source: String, _ pin: String, depth: Int = 0) -> Double {
        value(AIMPSkinSource(source, pin, names: skin.index.names), depth: depth)
    }

    func value(_ source: AIMPSkinSource, depth: Int = 0) -> Double {
        guard depth < 32 else { return 0 }
        switch source {
        case .page(let group): return Double(activePage(group, depth: depth))
        case .pointerOver(let name, let otherwise):
            guard let rect = host.feedback.hoverRects[name] else { return value(otherwise, depth: depth) }
            switch host.feedback.pointer {
            case .anywhere: return value(otherwise, depth: depth)
            case .outside: return 0
            case .at(let point): return rect.contains(point) ? 1 : 0
            }
        case .animatorFrame(let name, let otherwise):
            return state.animation[name].frame.map(Double.init) ?? value(otherwise, depth: depth)
        case .item(let name):
            return itemValue(name, depth: depth)
        case .value(let constant): return constant
        case .player(let pin): return host.value(pin)
        // Before the list has been drawn, any rows count.
        case .docked(let form): return isDocked(form) ? 1 : 0
        case .playlistScrolls:
            let rows = host.playlistIndices(matching: state.lists.playlistSearch).count
            return rows > (host.feedback.playlistRowsShown ?? 0) ? 1 : 0
        // The library's table and grouping presets are the library browser's, which shows its own
        // totals and groups: the skin's read-outs of them read nothing.
        case .table, .text: return 0
        case .libraryScanning: return host.player.libraryScanning ? 1 : 0
        // By depth as well: a value cut short near the depth limit is not one read from higher up.
        case .commutator(let name):
            let key = "\(depth) \(name)"
            if let known = commutators.values[key] { return known }
            let result = commutatorValue(name, depth: depth)
            commutators.values[key] = result
            return result
        // Text joined from its values, read as the number it spells, else 0 (Antares' source digit:
        // `%IFEqual(…)` to 0 for a file, 2 for radio). A trigger watches its inputs (`inputs(of:)`).
        case .concatenator(let name):
            return Double(concatenatorText(name, depth: depth + 1).trimmingCharacters(in: .whitespaces)) ?? 0
        // Read through its `Module`, as a position it holds is: `PositionDefault` 4 of 3 positions is 1.
        case .counter(let name):
            if let held = state.script[name].counter { return Double(held) }
            if name == "CounterPosition" { return host.value(.elapsed) }
            guard let provider = skin.index.providers[name] else { return 0 }
            if let link = provider.bindings["Position"] {
                return Double(wrapped(AIMPSkinScript.integer(value(of: link, depth: depth + 1)), counter: name))
            }
            return Double(wrapped(provider.positionDefault, counter: name))
        }
    }

    /// A commutator's `Result`: its `Expression` over its values, or with none its first value.
    private func commutatorValue(_ name: String, depth: Int) -> Double {
        guard let provider = skin.index.providers[name] else { return 0 }
        let links = provider.bindings.links
        // No `Expression`: it passes its first value on (Office 2016's volume read-out; 28 corpus skins).
        guard let expression = provider.expression else {
            return links.first { $0.target?.lowercased() == "value1" }.map { value(of: $0, depth: depth + 1) } ?? 0
        }
        var variables: [String: Double] = [:]
        for link in links {
            guard let target = link.target?.lowercased() else { continue }
            variables[target] = value(of: link, depth: depth + 1)
        }
        return skin.index.expression(expression)?.evaluate(variables: variables) ?? 0
    }
}

