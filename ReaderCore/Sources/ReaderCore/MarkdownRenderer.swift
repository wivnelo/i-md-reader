import Foundation
import Markdown

public struct ReaderHeading: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let level: Int
}

public struct RenderedDocument: Sendable {
    public let body: String
    public let headings: [ReaderHeading]
}

/// Emit an allowlisted HTML vocabulary from the AST. Never pass source HTML through.
public struct MarkdownRenderer {
    public init() {}
    public func render(_ source: String, hideFrontMatter: Bool = true, allowRelativeImages: Bool = true) -> RenderedDocument {
        var writer = SafeHTML(allowRelativeImages: allowRelativeImages)
        let document = Document(parsing: hideFrontMatter ? Self.withoutFrontMatter(source) : source)
        let body = writer.render(document)
        return RenderedDocument(body: body, headings: writer.headings)
    }

    static func withoutFrontMatter(_ source: String) -> String {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else { return source }
        return lines.dropFirst(end + 1).joined(separator: "\n")
    }
}

private struct SafeHTML {
    let allowRelativeImages: Bool
    var headings: [ReaderHeading] = []
    mutating func children(_ node: any Markup) -> String {
        var result = ""
        for child in node.children { result += render(child) }
        return result
    }
    mutating func render(_ node: any Markup) -> String {
        switch node {
        case let text as Markdown.Text: return escape(text.string)
        case let code as InlineCode: return "<code>\(escape(code.code))</code>"
        case let code as CodeBlock:
            let language = code.language ?? "Code"
            let grammar = language.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
            return "<section class=\"codeblock\"><header><span>\(escape(language))</span><button class=\"copy\" type=\"button\">复制</button></header><pre><code data-language=\"\(escape(grammar))\">\(escape(code.code))</code></pre></section>"
        case let heading as Heading:
            let base = heading.plainText.lowercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) || $0 == "-" || $0 == "_"
            }.map(String.init).joined().replacingOccurrences(of: " ", with: "-")
            var id = base.isEmpty ? "heading" : base
            var suffix = 1
            while headings.contains(where: { $0.id == id }) { id = "\(base.isEmpty ? "heading" : base)-\(suffix)"; suffix += 1 }
            headings.append(ReaderHeading(id: id, title: heading.plainText, level: heading.level))
            return "<h\(heading.level) id=\"\(id)\">\(children(heading))</h\(heading.level)>"
        case is Paragraph: return "<p>\(children(node))</p>"
        case is Strong: return "<strong>\(children(node))</strong>"
        case is Emphasis: return "<em>\(children(node))</em>"
        case is Strikethrough: return "<del>\(children(node))</del>"
        case is BlockQuote: return "<blockquote>\(children(node))</blockquote>"
        case is UnorderedList: return "<ul>\(children(node))</ul>"
        case let list as OrderedList: return "<ol start=\"\(list.startIndex)\">\(children(node))</ol>"
        case let item as ListItem:
            let checkbox: String
            if let state = item.checkbox {
                checkbox = "<input type=\"checkbox\" disabled \(state == .checked ? "checked" : "") aria-label=\"任务状态\">"
            } else { checkbox = "" }
            return "<li>\(checkbox)\(children(node))</li>"
        case let table as Table:
            var header = "", body = ""
            for (index, cell) in table.head.children.enumerated() {
                header += "<th\(alignment(table, index))>\(children(cell))</th>"
            }
            for row in table.body.children {
                body += "<tr>"
                for (index, cell) in row.children.enumerated() { body += "<td\(alignment(table, index))>\(children(cell))</td>" }
                body += "</tr>"
            }
            return "<div class=\"table-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"表格\"><table><thead><tr>\(header)</tr></thead><tbody>\(body)</tbody></table></div>"
        case let link as Markdown.Link:
            guard let destination = safeDestination(link.destination, image: false) else { return children(node) }
            return "<a href=\"\(escape(destination))\">\(children(node))</a>"
        case let image as Markdown.Image:
            guard allowRelativeImages else { return "<span class=\"resource-note\">[图片暂未加载]</span>" }
            guard let source = safeDestination(image.source, image: true) else { return "<span class=\"resource-note\">[图片未加载：仅支持本地相对图片]</span>" }
            return "<img src=\"\(escape(source))\" alt=\"\(escape(image.plainText))\" loading=\"lazy\">"
        case is ThematicBreak: return "<hr>"
        case is LineBreak: return "<br>"
        case is SoftBreak: return "\n"
        case let raw as HTMLBlock: return "<pre class=\"raw-html\">\(escape(raw.rawHTML))</pre>"
        case let raw as InlineHTML: return escape(raw.rawHTML)
        default: return children(node)
        }
    }
    func alignment(_ table: Table, _ index: Int) -> String {
        guard index < table.columnAlignments.count, let value = table.columnAlignments[index] else { return "" }
        let name: String
        switch value { case .left: name = "left"; case .center: name = "center"; case .right: name = "right" }
        return " style=\"text-align:\(name)\""
    }
    func safeDestination(_ value: String?, image: Bool) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if let scheme = URLComponents(string: value)?.scheme {
            return !image && ["http", "https", "mailto"].contains(scheme.lowercased()) ? value : nil
        }
        return value
    }
    func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
