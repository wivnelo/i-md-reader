import Foundation

extension ReadableFile {
    /// Render any readable file. Markdown keeps its renderer; everything else is one escaped, numbered block.
    public static func render(_ text: String, name: String, allowRelativeImages: Bool = true) -> RenderedDocument {
        guard case let .code(grammar, label)? = kind(named: name) else {
            return MarkdownRenderer().render(text, allowRelativeImages: allowRelativeImages)
        }
        return renderCode(text, grammar: grammar, label: label)
    }

    static func renderCode(_ text: String, grammar: String?, label: String) -> RenderedDocument {
        var source = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if source.hasSuffix("\n") { source.removeLast() }
        let lineCount = max(1, source.reduce(into: 1) { count, character in if character == "\n" { count += 1 } })
        var gutter = ""
        gutter.reserveCapacity(lineCount * 5)
        for line in 1...lineCount { gutter += line == 1 ? "1" : "\n\(line)" }
        let language = grammar.map { " data-language=\"\(escape($0))\"" } ?? ""
        let body = "<section class=\"codeblock codefile\"><header><span>\(escape(label))</span><button class=\"copy\" type=\"button\">复制</button></header>"
            + "<div class=\"codefile-scroll\"><pre class=\"gutter\" aria-hidden=\"true\">\(gutter)</pre>"
            + "<pre class=\"source\"><code\(language)>\(escape(source))</code></pre></div></section>"
        return RenderedDocument(body: body, headings: [])
    }

    fileprivate static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count + value.utf8.count / 8)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
