import Foundation

/// A small, forgiving HTML tokenizer for the raw HTML that Markdown allows. It only splits text from tags;
/// the renderer decides what to keep. Malformed input degrades to text, never to markup.
enum RawHTMLToken: Equatable {
    case text(String)
    case start(name: String, attributes: [(name: String, value: String)], selfClosing: Bool)
    case end(String)

    static func == (lhs: RawHTMLToken, rhs: RawHTMLToken) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)), let (.end(a), .end(b)): return a == b
        case let (.start(a, x, s), .start(b, y, t)):
            return a == b && s == t && x.map(\.name) == y.map(\.name) && x.map(\.value) == y.map(\.value)
        default: return false
        }
    }

    /// Comments, doctypes and processing instructions are dropped. Tag and attribute names are lowercased;
    /// attribute values have character references decoded.
    static func tokenize(_ html: String) -> [RawHTMLToken] {
        let bytes = Array(html.utf8)
        var tokens: [RawHTMLToken] = []
        var text: [UInt8] = []
        var index = 0
        func flush() { if !text.isEmpty { tokens.append(.text(String(decoding: text, as: UTF8.self))); text.removeAll() } }
        func skip(past terminator: [UInt8], from start: Int) -> Int {
            var cursor = start
            while cursor + terminator.count <= bytes.count {
                if Array(bytes[cursor..<cursor + terminator.count]) == terminator { return cursor + terminator.count }
                cursor += 1
            }
            return bytes.count
        }
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<"), index + 1 < bytes.count else { text.append(bytes[index]); index += 1; continue }
            let next = bytes[index + 1]
            if bytes[index...].starts(with: Array("<!--".utf8)) {
                flush(); index = skip(past: Array("-->".utf8), from: index + 4)
            } else if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                flush(); index = skip(past: [UInt8(ascii: ">")], from: index + 2)
            } else if let (token, end) = tag(bytes, at: index) {
                flush(); tokens.append(token); index = end
            } else {
                text.append(bytes[index]); index += 1
            }
        }
        flush()
        return tokens
    }

    private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private static func isSpace(_ byte: UInt8) -> Bool { [9, 10, 12, 13, 32].contains(byte) }

    /// Parses `<name ...>` or `</name ...>` starting at `start`; nil if it is not a complete tag.
    private static func tag(_ bytes: [UInt8], at start: Int) -> (RawHTMLToken, Int)? {
        var cursor = start + 1
        let closing = bytes[cursor] == UInt8(ascii: "/")
        if closing { cursor += 1 }
        guard cursor < bytes.count, isLetter(bytes[cursor]) else { return nil }
        let nameStart = cursor
        while cursor < bytes.count, !isSpace(bytes[cursor]), bytes[cursor] != UInt8(ascii: "/"), bytes[cursor] != UInt8(ascii: ">") { cursor += 1 }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
        var attributes: [(name: String, value: String)] = []
        var selfClosing = false
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == UInt8(ascii: ">") {
                let token: RawHTMLToken = closing ? .end(name) : .start(name: name, attributes: attributes, selfClosing: selfClosing)
                return (token, cursor + 1)
            }
            if isSpace(byte) || byte == UInt8(ascii: "/") {
                selfClosing = byte == UInt8(ascii: "/"); cursor += 1; continue
            }
            selfClosing = false
            let attributeStart = cursor
            while cursor < bytes.count, !isSpace(bytes[cursor]), ![UInt8(ascii: "/"), UInt8(ascii: ">"), UInt8(ascii: "=")].contains(bytes[cursor]) || cursor == attributeStart { cursor += 1 }
            let attribute = String(decoding: bytes[attributeStart..<cursor], as: UTF8.self).lowercased()
            while cursor < bytes.count, isSpace(bytes[cursor]) { cursor += 1 }
            var value = ""
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "=") {
                cursor += 1
                while cursor < bytes.count, isSpace(bytes[cursor]) { cursor += 1 }
                guard cursor < bytes.count else { return nil }
                let quote = bytes[cursor]
                if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                    guard let close = bytes[(cursor + 1)...].firstIndex(of: quote) else { return nil }
                    value = String(decoding: bytes[(cursor + 1)..<close], as: UTF8.self)
                    cursor = close + 1
                } else {
                    let valueStart = cursor
                    while cursor < bytes.count, !isSpace(bytes[cursor]), bytes[cursor] != UInt8(ascii: ">") { cursor += 1 }
                    value = String(decoding: bytes[valueStart..<cursor], as: UTF8.self)
                }
            }
            if !attributes.contains(where: { $0.name == attribute }) { attributes.append((attribute, decodeReferences(value))) }
        }
        return nil
    }

    /// Decodes numeric and the common named character references; unknown names stay literal.
    static func decodeReferences(_ value: String) -> String {
        guard value.contains("&") else { return value }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "colon": ":", "tab": "\t", "newline": "\n"]
        var result = ""
        var rest = Substring(value)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            let body = after.prefix { $0.isLetter || $0.isNumber || $0 == "#" }
            var replacement: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let scalar = digits.first.map { $0 == "x" || $0 == "X" } == true
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                replacement = scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? (body.count > 1 ? "\u{FFFD}" : nil)
            } else { replacement = named[String(body)] }
            if let replacement, !body.isEmpty {
                result += replacement
                rest = after[body.endIndex...]
                if rest.first == ";" { rest = rest.dropFirst() }
            } else {
                result += "&"
                rest = after
            }
        }
        return result + rest
    }
}
