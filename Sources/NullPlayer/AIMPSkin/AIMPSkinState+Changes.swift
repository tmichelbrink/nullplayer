import Foundation

extension AIMPSkinState {
    /// What a script job changed of the state it ran on, part by part: each object's page,
    /// counter, timer or lamp, each variable, it set or cleared. Worked out where the job ran, off
    /// the main thread, and applied on the main actor over the state as it stands by then: a change
    /// made there while the job ran (a list scrolled, a page turned by a key) stays, unless the
    /// scripts changed that same part of that same object, which is theirs.
    struct Changes: Sendable {
        typealias Edit = @Sendable (inout AIMPSkinState) -> Void
        private var edits: [Edit] = []

        var isEmpty: Bool { edits.isEmpty }

        /// From `before` to `after`.
        init(from before: AIMPSkinState, to after: AIMPSkinState) {
            guard before != after else { return }
            for field in Self.fields { field.compare(before, after, &edits) }
        }

        func apply(to state: inout AIMPSkinState) {
            for edit in edits { edit(&state) }
        }

        /// Every part of the state, keyed ones by key and records part by part. A part left out
        /// here would lose what the scripts change in it (`AIMPSkinStateChangesTests` sets every one).
        private static let fields: [Field] = [
            .records(\.script.objects, [
                .of(\.activePage), .of(\.counter), .of(\.visible), .of(\.autoHidden), .of(\.properties),
                .of(\.expression), .of(\.docked), .of(\.parent), .of(\.timerEnabled), .of(\.timerInterval),
                .of(\.timerGate), .of(\.margins), .of(\.text), .of(\.scrollTop), .of(\.visibleGate),
            ]),
            .keyed(\.script.resourceLinks), .keyed(\.script.config), .keyed(\.script.variables), .whole(\.script.visualMode),
            .records(\.animation.objects, [
                .of(\.timerFired), .of(\.scriptInputs), .of(\.frame), .of(\.stepped), .of(\.opacity),
            ]),
            .whole(\.lists),
        ]

        /// One part of the state, and how a change to it is found and made.
        private struct Field: Sendable {
            let compare: @Sendable (AIMPSkinState, AIMPSkinState, inout [Edit]) -> Void

            /// A dictionary, changed key by key: each key set to its new value, or cleared.
            static func keyed<Key: Hashable & Sendable, Value: Equatable & Sendable>(
                _ path: WritableKeyPath<AIMPSkinState, [Key: Value]> & Sendable
            ) -> Field {
                Field { before, after, edits in
                    let old = before[keyPath: path], new = after[keyPath: path]
                    guard old != new else { return }
                    let set = new.filter { old[$0.key] != $0.value }
                    let cleared = old.keys.filter { new[$0] == nil }
                    edits.append { state in
                        for (key, value) in set { state[keyPath: path][key] = value }
                        for key in cleared { state[keyPath: path][key] = nil }
                    }
                }
            }

            /// Records by object name, changed part by part: each part of each record set to its new value.
            static func records<Record>(_ path: WritableKeyPath<AIMPSkinState, Records<Record>> & Sendable,
                                        _ parts: [Part<Record>]) -> Field {
                Field { before, after, edits in
                    let old = before[keyPath: path], new = after[keyPath: path]
                    guard old != new else { return }
                    for name in Set(old.byName.keys).union(new.byName.keys) where old[name] != new[name] {
                        for part in parts {
                            guard let edit = part.change(old[name], new[name]) else { continue }
                            edits.append { edit(&$0[keyPath: path][name]) }
                        }
                    }
                }
            }

            /// A value changed as a whole.
            static func whole<Value: Equatable & Sendable>(_ path: WritableKeyPath<AIMPSkinState, Value> & Sendable) -> Field {
                Field { before, after, edits in
                    let new = after[keyPath: path]
                    guard before[keyPath: path] != new else { return }
                    edits.append { $0[keyPath: path] = new }
                }
            }
        }

        /// One part of a record, and how a change to it is made.
        private struct Part<Record: Sendable>: Sendable {
            let change: @Sendable (Record, Record) -> (@Sendable (inout Record) -> Void)?

            static func of<Value: Equatable & Sendable>(_ path: WritableKeyPath<Record, Value> & Sendable) -> Part {
                Part { old, new in
                    let value = new[keyPath: path]
                    guard old[keyPath: path] != value else { return nil }
                    return { $0[keyPath: path] = value }
                }
            }
        }
    }
}
