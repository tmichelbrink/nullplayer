import Foundation

/// A FastScript interpreter for AIMP skin scripts (`.fsxml`, FastScript's syntax tree; the format
/// is `reference/format.md` § *Scripts*). Each script is compiled once as the skin loads
/// (`AIMPSkinScript+Syntax.swift`: a tree it does not take is a load-time finding) and run by
/// `Run` on an `Engine`, one per job (a tick, the load, an event: `Job`), which owns the state the
/// scripts change and what they ask of the player. It runs the subset skins use to wire themselves: Pascal's statements
/// and expressions, the Delphi run-time functions skins call (`Builtin`), and the host's calls and
/// objects (`AIMPSkinScript+HostBridge.swift`):
/// - `BindingsGetDataAsText/AsInteger/AsFloat/AsBoolean(source, pin)` read the dataflow;
/// - `FindResource(id).Set('ID', target)` repoints a resource alias (Vega's cassette sticker);
/// - `FindObject(name).Set(property, value)` turns a tabbed group, moves a counter, shows an item,
///   sets the player's volume, balance, speed, position or EQ, restyles a control;
/// - `FindObject('acPlayerPlay').Execute` asks the window for that action.
/// Anything else stops that run (`Unsupported`), even inside the skin's own `try … except`: the
/// skin keeps the state it had, and the gap shows (`AIMP_RENDER_SCRIPTS=1`).
///
/// A `ScriptableOperatorCounter` provider runs its script when the value bound to its `Position`
/// changes, with `State` the new value; `State` after the run is the counter's position
/// (`Engine.settle`). A control's `OnClick` names a `ScriptableEventHandler`, run with `Sender` the
/// control (`Engine.handle`).
enum AIMPSkinScript {
    struct Unsupported: Error, CustomStringConvertible {
        var what = ""
        var description: String { what }
    }

    /// What one tick or one event may spend on scripts, shared by every run it starts, nested runs
    /// and routine calls included. A run that overspends stops (`Spent`), and so does each later
    /// run on the same budget: a runaway skin costs a bounded slice of one frame, and recursion
    /// stops long before the stack does.
    ///
    /// Scripts run on the AIMP queue, off the main thread (`AIMPSkinScriptScheduler`), and the
    /// skin's frames draw on that same queue after them, so the step limit is what one tick may
    /// hold that queue for: a runaway skin delays its own next frame, never the app. Sized against
    /// the gate corpus in an optimized build: the busiest skin's tick takes 1,734 steps
    /// (Technicss, under 1 ms), a load or a click at most 64; a runaway loop of host calls spends
    /// 20,000 steps in about 10 ms, a third of a frame at 30 fps.
    ///
    /// Steps alone do not bound the work: one step can copy a long text. So text work is charged
    /// too, by the bytes each `+`, `Insert`, `Format` and string built-in reads and makes
    /// (`charge`), against `byteLimit`. The busiest gate skin's tick moves a few kilobytes.
    final class Budget {
        static let stepLimit = 20_000
        static let depthLimit = 32
        static let byteLimit = 4 << 20
        private(set) var steps = 0
        private(set) var bytes = 0
        private var depth = 0

        var isSpent: Bool { steps >= Self.stepLimit || bytes >= Self.byteLimit }

        /// Thrown when the budget runs out; a script's `except` does not catch it.
        struct Spent: Error, CustomStringConvertible {
            let what: String
            var description: String { what }
        }

        func step() throws {
            steps += 1
            guard steps < Self.stepLimit else { throw Spent(what: "step budget") }
        }

        /// Charges `count` bytes of text work.
        func charge(_ count: Int) throws {
            bytes += count
            guard bytes < Self.byteLimit else { throw Spent(what: "text budget") }
        }

        /// `body`, one routine or handler deeper.
        func nested<T>(_ body: () throws -> T) throws -> T {
            guard depth < Self.depthLimit else { throw Spent(what: "call depth") }
            depth += 1
            defer { depth -= 1 }
            return try body()
        }
    }

    /// A skin's scripts, compiled as it loads (off the main thread): `.fsxml` in `.acs5`, and the
    /// compiled `.script`s some `.acs4` carry (a `.fsxml` of the same name wins). A script stored
    /// as Pascal source is not one this engine runs, and is left out.
    struct Library: Sendable {
        /// By lowercased name without its extension.
        var programs: [String: Program] = [:]
        /// The compiled scripts that did not decode or compile, by name, with why: each is also a
        /// load-time finding (`AM0008`).
        var unreadable: [String: String] = [:]

        init(_ archive: AIMPSkinArchive, findings: inout [AIMPSkinFinding]) {
            for ext in [".script", ".fsxml"] {
                for (name, entry) in archive.entries.sorted(by: { $0.key < $1.key }) where name.hasSuffix(ext) {
                    guard let data = try? archive.payload(entry), data.prefix(8) == Data("FSXMLBIN".utf8) else { continue }
                    let stem = String(name.dropLast(ext.count))
                    do {
                        programs[stem] = try compile(parse(data))
                        unreadable[stem] = nil
                    } catch {
                        if programs[stem] == nil { unreadable[stem] = "\(error)" }
                        findings.append(AIMPSkinFinding(.entryUnreadable, "\(entry.name): \(error)"))
                    }
                }
            }
        }
    }

    /// A script's number as a whole one, toward zero as Delphi's `Trunc` takes it: an index, a loop
    /// bound, a position, a character code. A number no `Int` holds (`1e300`, or a text such as
    /// `'inf'` or `'nan'` read as a number) stops at the nearest end, and NaN reads 0, where a bare
    /// `Int(_:)` would bring the app down on a skin's arithmetic.
    static func integer(_ number: Double) -> Int {
        guard !number.isNaN else { return 0 }
        let whole = number.rounded(.towardZero)
        if whole >= Double(Int.max) { return .max }
        if whole <= Double(Int.min) { return .min }
        return Int(whole)
    }

    /// A timer's or animator's interval in seconds as AIMP keeps it: both run on Windows timers, which
    /// fire on 15.6 ms ticks, so an interval waits for the next tick at or after it (Revox's 18 ms
    /// reels turn every 31 ms), and skins are tuned so. An animator asks for at least a millisecond.
    static func tickedInterval(_ milliseconds: Double) -> Double {
        (milliseconds / 15.625).rounded(.up) * 15.625 / 1_000
    }
}
