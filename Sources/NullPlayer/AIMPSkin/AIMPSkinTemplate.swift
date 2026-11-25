import Foundation

/// AIMP's text templates, as `TextDisplay` `Template` and binding `TextFormat` write them:
/// `%IF(%R,%R - ,)%T`, `%Up(%R)`, `%Replace(%T,;, / )`, `%Char(44)`, `%StrLeft(%T,3)`. Fields are `%T`/`%Title`,
/// `%R`/`%Artist`, `%A`/`%Album`; a function's arguments split on top-level commas. Unknown fields read
/// empty; an unknown function reads as its first argument (empty with none).
enum AIMPSkinTemplate {
    /// The most characters a template's text holds: far more than any skin shows in one line.
    static let textLimit = 4_096

    /// `variables` are a text provider's inputs (`%Value1`, `%TextValue1`); `value` is the number a
    /// display is bound to, for `%time(MS;:;)`.
    static func format(_ template: String, host: AIMPSkinHostState, variables: [String: String] = [:], value: Double? = nil) -> String {
        var parser = Parser(chars: Array(template), host: host,
                            variables: Dictionary(variables.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a }),
                            value: value)
        return parser.text(until: [])
    }

    private struct Parser {
        let chars: [Character]
        let host: AIMPSkinHostState
        let variables: [String: String]
        let value: Double?
        var at = 0
        /// Calls open around the one being read (`field`).
        var depth = 0

        /// Text up to (not past) one of `stops` at this nesting level, or the end.
        mutating func text(until stops: Set<Character>) -> String {
            var out = ""
            while at < chars.count, !stops.contains(chars[at]) {
                if chars[at] == "%" { out += field() } else { out.append(chars[at]); at += 1 }
                // Past `textLimit` the rest of the template reads empty: concatenators feeding each
                // other (`%TextValue1%TextValue1`, eight deep) would otherwise double their text at
                // every level.
                if out.utf8.count > AIMPSkinTemplate.textLimit {
                    at = chars.count
                    return String(out.prefix(AIMPSkinTemplate.textLimit))
                }
            }
            return out
        }

        mutating func field() -> String {
            at += 1  // %
            var name = ""
            while at < chars.count, chars[at].isLetter || chars[at].isNumber { name.append(chars[at]); at += 1 }
            guard at < chars.count, chars[at] == "(" else { return value(of: name) }
            // Calls nested past 64 are no skin's, and each one is a frame of the stack: the rest of
            // the template reads empty.
            guard depth < 64 else { at = chars.count; return "" }
            depth += 1
            defer { depth -= 1 }
            at += 1
            var args: [String] = []
            while true {
                args.append(text(until: [",", ")"]))
                guard at < chars.count else { break }
                let c = chars[at]
                at += 1
                if c == ")" { break }
            }
            return call(name.lowercased(), args)
        }

        /// Short fields (`%T`) and long ones (`%Title`) both occur. Short ones are case-sensitive
        /// (`%a` is the artist, `%A` the album); long ones are not (`%playcount`, `%PlayCount`).
        func value(of field: String) -> String {
            if let variable = variables[field.lowercased()] { return variable }
            let player = host.player
            switch field {
            case "IN": return player.playlistIndex >= 0 ? String(player.playlistIndex + 1) : ""
            case "E": return player.fileType
            case "T": return player.title
            case "R", "a": return player.artist
            case "A": return player.album
            case "Y": return year
            case "G": return player.genre
            case "B": return bitrate
            case "H": return sampleRate
            case "C": return channels
            case "L": return duration
            case "S": return fileSize
            default: break
            }
            switch field.lowercased() {
            // `%FileFormat` is the type AIMP names the file by, which NullPlayer takes from its
            // extension as `%E` does, and `%FileName` the name without it: the Windows Media Player
            // skins write `%FileName.%FileFormat`, Office 2016 `%IF(%FileFormat,%FileFormat, ,)...`.
            case "fileext", "fileformat": return player.fileType
            case "title": return player.title
            case "filename": return player.fileName.isEmpty ? player.title : player.fileName
            case "artist", "albumartist": return player.artist
            case "album": return player.album
            case "year": return year
            case "genre": return player.genre
            case "bitrate": return bitrate
            case "samplerate": return sampleRate
            case "channels": return channels
            case "duration": return duration
            case "filesize": return fileSize
            case "filedir": return player.fileDirectory
            case "fileparentdir": return (player.fileDirectory as NSString).lastPathComponent
            case "disknumber": return player.discNumber > 0 ? String(player.discNumber) : ""
            // The library's statistics: Windows Media Player 8 and 11 write `%PlayCount /
            // %LastPlayDate %LastPlayTime`. AIMP 5.40 shows "-" for a file it has no statistics for.
            case "playcount": return player.playCount.map(String.init) ?? "-"
            case "lastplaydate": return player.lastPlayed == nil ? "-" : date(player.lastPlayed)
            case "lastplaytime": return player.lastPlayed == nil ? "-" : time(player.lastPlayed)
            case "lastplaydateandtime": return player.lastPlayed == nil ? "-" : dateAndTime(player.lastPlayed)
            case "filecreateddate": return date(player.fileCreated)
            case "filecreatedtime": return time(player.fileCreated)
            case "filecreateddateandtime": return dateAndTime(player.fileCreated)
            case "filemodifieddate": return date(player.fileModified)
            case "filemodifiedtime": return time(player.fileModified)
            case "filemodifieddateandtime": return dateAndTime(player.fileModified)
            case "newline": return "\n"
            // Tags NullPlayer does not read read empty, as AIMP shows a file without them.
            case "trackgain", "albumgain", "trackpeak", "albumpeak", "bitdepth", "lyricist", "mood",
                 "conductor", "encodedby", "tracktotal", "disktotal":
                return ""
            // The templates AIMP's user sets in its options: NullPlayer has none, so AIMP's own
            // title line, the artist then the title.
            case let user where user.hasPrefix("usertemplate"):
                return player.artist.isEmpty ? player.title : player.artist + " - " + player.title
            default: return ""
            }
        }

        var year: String { host.player.year > 0 ? String(host.player.year) : "" }
        var bitrate: String { host.player.bitrate > 0 ? "\(host.player.bitrate) kbps" : "" }
        /// Whole kilohertz, rounded down, as AIMP 5.40 writes them (44100 is "44 kHz").
        var sampleRate: String { host.player.sampleRate > 0 ? "\(host.player.sampleRate / 1000) kHz" : "" }
        var channels: String {
            let n = host.player.channels
            return n == 1 ? "Mono" : n == 2 ? "Stereo" : n > 2 ? "\(n)" : ""
        }
        var duration: String {
            let s = host.player.durationSeconds
            return s > 0 ? AIMPSkinFormat.minutes(s) : ""
        }
        var fileSize: String { host.player.fileSize > 0 ? AIMPSkinFormat.size(Double(host.player.fileSize)) : "" }

        /// Dates and times in the user's short formats, as AIMP takes Windows'.
        func date(_ date: Date?) -> String { date.map { Self.dates.string(from: $0) } ?? "" }
        func time(_ date: Date?) -> String { date.map { Self.times.string(from: $0) } ?? "" }
        func dateAndTime(_ date: Date?) -> String { date.map { Self.dates.string(from: $0) + " " + Self.times.string(from: $0) } ?? "" }
        static let dates: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f }()
        static let times: DateFormatter = { let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f }()

        /// Argument `i` as a whole number, 0 when absent or not one.
        func number(_ args: [String], _ i: Int) -> Int {
            i < args.count ? AIMPSkinScript.integer(Double(args[i].trimmingCharacters(in: .whitespaces)) ?? 0) : 0
        }

        func call(_ name: String, _ args: [String]) -> String {
            switch name {
            // Empty is false, and so is a zero: a counter's `%Value4` reads "0" until it is pressed
            // (Terran's timer shows the track's time, not the sleep timer, until it is clicked; AIMP
            // 5.40 shows AndroEvolution's speaker unmuted and Soot's switches off). AIMP's playlist
            // line formatter is another engine: there `%IF(0,yes,no)` is "yes".
            case "if":
                guard args.count >= 2 else { return "" }
                let condition = args[0].trimmingCharacters(in: .whitespaces)
                return !condition.isEmpty && Double(condition) != 0 ? args[1] : (args.count > 2 ? args[2] : "")
            case "up": return (args.first ?? "").uppercased()
            case "low": return (args.first ?? "").lowercased()
            case "replace":
                guard args.count >= 3, !args[1].isEmpty else { return args.first ?? "" }
                // One that could grow the text past 64K characters is left undone: nested, each would
                // multiply the last.
                guard args[2].count <= args[1].count || Double(args[0].count / args[1].count) * Double(args[2].count) <= 65_536
                else { return args[0] }
                return args[0].replacingOccurrences(of: args[1], with: args[2])
            case "char": return (args.first.flatMap { Int($0) }.flatMap { UnicodeScalar($0) }).map { String(Character($0)) } ?? ""
            // Text and arithmetic, 1-based as AIMP counts (Soot splits its "Off|On" language string:
            // `%StrLeft(%TextValue1,%Dec(%StrPos(|,%TextValue1),1))`).
            case "length": return String((args.first ?? "").count)
            case "strpos":
                guard args.count >= 2, !args[0].isEmpty, let range = args[1].range(of: args[0]) else { return "0" }
                return String(args[1].distance(from: args[1].startIndex, to: range.lowerBound) + 1)
            case "strleft": return String((args.first ?? "").prefix(max(0, number(args, 1))))
            case "strright": return String((args.first ?? "").suffix(max(0, number(args, 1))))
            case "copy":
                let text = Array(args.first ?? ""), from = max(1, number(args, 1)), count = max(0, number(args, 2))
                guard from <= text.count else { return "" }
                return String(text[(from - 1)..<(from - 1 + min(count, text.count - (from - 1)))])
            case "trim": return (args.first ?? "").trimmingCharacters(in: .whitespaces)
            // Wrapping, as Delphi's unchecked integers do, rather than trapping.
            case "inc": return String(number(args, 0) &+ (args.count > 1 ? number(args, 1) : 1))
            case "dec": return String(number(args, 0) &- (args.count > 1 ? number(args, 1) : 1))
            // `%IFEqual(a,b,then,else)` and kin compare numbers when both are, else text.
            case "ifequal", "ifgreater", "ifgreaterorequal", "ifless", "iflessorequal":
                guard args.count >= 3 else { return "" }
                let order: ComparisonResult
                if let a = Double(args[0].trimmingCharacters(in: .whitespaces)), let b = Double(args[1].trimmingCharacters(in: .whitespaces)) {
                    order = a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
                } else {
                    order = args[0].compare(args[1])
                }
                let holds = switch name {
                case "ifequal": order == .orderedSame
                case "ifgreater": order == .orderedDescending
                case "ifgreaterorequal": order != .orderedAscending
                case "ifless": order == .orderedAscending
                default: order != .orderedDescending
                }
                return holds ? args[2] : (args.count > 3 ? args[3] : "")
            // `%time(HMS;:;)`: the bound number of seconds as h:mm:ss (or m:ss for `MS`); `Z` leaves
            // out the hours while there are none (M5's 50-px wave-bar times: 2:39, not 0:02:39).
            case "time":
                let seconds = AIMPSkinScript.integer(value ?? 0)
                let spec = (args.first ?? "").split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                let separator = spec.count > 1 && !spec[1].isEmpty ? spec[1] : ":"
                let skipsZero = spec.count > 2 && spec[2].uppercased().contains("Z")
                // The separator is the skin's text: joined, never a format string.
                let fields = (spec.first ?? "MS").uppercased().hasPrefix("H") && !(skipsZero && seconds < 3_600)
                    ? [String(seconds / 3_600), String(format: "%02d", seconds / 60 % 60), String(format: "%02d", seconds % 60)]
                    : [String(seconds / 60), String(format: "%02d", seconds % 60)]
                return fields.joined(separator: separator)
            default: return args.first ?? ""
            }
        }
    }
}
