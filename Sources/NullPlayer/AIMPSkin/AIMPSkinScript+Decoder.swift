import Foundation

extension AIMPSkinScript {
    // MARK: - FSXMLBIN

    /// `FSXMLBIN`, then nodes of `{ u16 + UTF-16LE tag, u16 + UTF-16LE attribute text, u32 child count }`.
    static func parse(_ data: Data) throws -> AIMPNode {
        guard data.count > 8, data.prefix(8) == Data("FSXMLBIN".utf8) else { throw Malformed(description: "not FSXMLBIN") }
        var reader = AIMPSkinBytes(data, code: .entryUnreadable)
        reader.offset = 8
        var nodes = 0
        func node(_ depth: Int) throws -> AIMPNode {
            nodes += 1
            guard depth < AIMPSkinPolicy.xmlDepth, nodes < AIMPSkinPolicy.xmlNodes else { throw Malformed(description: "too deep") }
            let tag = try reader.utf16(units: reader.u16())
            var attributes: [String: String] = [:]
            var rest = Substring(try reader.utf16(units: reader.u16()))
            // `name="value"` pairs; a value never holds a double quote.
            while let eq = rest.firstIndex(of: "=") {
                let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
                let afterQuote = rest.index(eq, offsetBy: 2, limitedBy: rest.endIndex) ?? rest.endIndex
                guard let close = rest[afterQuote...].firstIndex(of: "\"") else { break }
                attributes[key] = decodeEntities(String(rest[afterQuote..<close]))
                rest = rest[rest.index(after: close)...]
            }
            let count = try reader.u32()
            var children: [AIMPNode] = []
            for _ in 0..<count { children.append(try node(depth + 1)) }
            return AIMPNode(tag: tag, attributes: attributes, children: children, text: nil)
        }
        return try node(0)
    }

    /// XML character references in attribute text (`&#60;&#62;` and `&#x3C;&#x3E;` are `<>`); an
    /// unterminated `&` stays as written.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            guard let semi = rest[amp...].firstIndex(of: ";") else { break }
            out += rest[..<amp]
            let entity = rest[rest.index(after: amp)..<semi]
            switch entity {
            case "lt": out += "<"
            case "gt": out += ">"
            case "amp": out += "&"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                let number = entity.dropFirst()
                let code = number.first == "x" || number.first == "X" ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                if entity.hasPrefix("#"), let code, let scalar = UnicodeScalar(code) {
                    out.append(Character(scalar))
                } else {
                    out += rest[amp...semi]
                }
            }
            rest = rest[rest.index(after: semi)...]
        }
        return out + rest
    }
}
