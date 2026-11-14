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

/// Emit an allowlisted HTML vocabulary from the AST. Source HTML is re-tokenized and only presentational
/// elements and attributes are re-serialized (GitHub-style); anything else is dropped, never passed through.
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
    /// Raw HTML elements still open. Each Markdown container is a scope: end tags never close elements
    /// opened outside it, and whatever its own raw HTML left open is closed when it ends.
    var open: [(name: String, emitted: Bool)] = []
    var floor = 0
    /// A dropped element (script, style…) whose content is skipped until its end tag.
    var suppressed: String?
    mutating func children(_ node: any Markup) -> String {
        var result = ""
        for child in node.children { result += render(child) }
        return result
    }
    mutating func scoped(_ node: any Markup) -> String {
        let saved = (floor, suppressed)
        floor = open.count
        let result = children(node) + close(downTo: floor)
        (floor, suppressed) = saved
        return result
    }
    mutating func render(_ node: any Markup) -> String {
        if suppressed != nil, node is InlineMarkup, !(node is InlineHTML) { return "" }
        switch node {
        case is Document: return scoped(node)
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
            return "<h\(heading.level) id=\"\(id)\">\(scoped(heading))</h\(heading.level)>"
        case is Paragraph: return "<p>\(scoped(node))</p>"
        case is Strong: return "<strong>\(scoped(node))</strong>"
        case is Emphasis: return "<em>\(scoped(node))</em>"
        case is Strikethrough: return "<del>\(scoped(node))</del>"
        case is BlockQuote: return "<blockquote>\(scoped(node))</blockquote>"
        case is UnorderedList: return "<ul>\(children(node))</ul>"
        case let list as OrderedList: return "<ol start=\"\(list.startIndex)\">\(children(node))</ol>"
        case let item as ListItem:
            let checkbox: String
            if let state = item.checkbox {
                checkbox = "<input type=\"checkbox\" disabled \(state == .checked ? "checked" : "") aria-label=\"任务状态\">"
            } else { checkbox = "" }
            return "<li>\(checkbox)\(scoped(node))</li>"
        case let table as Table:
            var header = "", body = ""
            for (index, cell) in table.head.children.enumerated() {
                header += "<th\(alignment(table, index))>\(scoped(cell))</th>"
            }
            for row in table.body.children {
                body += "<tr>"
                for (index, cell) in row.children.enumerated() { body += "<td\(alignment(table, index))>\(scoped(cell))</td>" }
                body += "</tr>"
            }
            return "<div class=\"table-scroll\" tabindex=\"0\" role=\"region\" aria-label=\"表格\"><table><thead><tr>\(header)</tr></thead><tbody>\(body)</tbody></table></div>"
        case let link as Markdown.Link:
            guard let destination = safeDestination(link.destination, image: false) else { return scoped(node) }
            return "<a href=\"\(escape(destination))\">\(scoped(node))</a>"
        case let image as Markdown.Image:
            guard allowRelativeImages else { return "<span class=\"resource-note\" data-reader-message=\"folder-access\">图片需要所在文件夹的访问权限</span>" }
            guard let source = safeDestination(image.source, image: true) else { return "<span class=\"resource-note\" data-reader-message=\"unsupported-image\">暂不支持此图片地址</span>" }
            return "<img src=\"\(escape(source))\" alt=\"\(escape(image.plainText))\" loading=\"lazy\">"
        case is ThematicBreak: return "<hr>"
        case is LineBreak: return "<br>"
        case is SoftBreak: return "\n"
        case let raw as HTMLBlock: return html(raw.rawHTML, block: true)
        case let raw as InlineHTML: return html(raw.rawHTML, block: false)
        default: return children(node)
        }
    }

    // MARK: Raw HTML (GitHub-style allowlist)

    static let allowedElements: Set<String> = [
        "p", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "img", "a", "strong", "em", "b", "i", "u", "s", "del", "ins",
        "sub", "sup", "small", "mark", "br", "hr", "picture", "source", "details", "summary", "kbd", "code", "pre", "samp", "var",
        "table", "thead", "tbody", "tfoot", "caption", "tr", "th", "td", "ul", "ol", "li", "dl", "dt", "dd", "blockquote", "q", "abbr", "cite"
    ]
    static let voidElements: Set<String> = ["img", "br", "hr", "source"]
    /// Dropped together with everything up to their end tag.
    static let droppedWithContent: Set<String> = [
        "script", "style", "iframe", "object", "form", "textarea", "select", "noscript", "template", "title", "svg", "math",
        "applet", "frameset", "noembed", "noframes", "xmp", "plaintext"
    ]
    /// May stay open across sibling blocks, as in `<div align="center">` … Markdown … `</div>`.
    static let blockContainers: Set<String> = [
        "div", "details", "blockquote", "table", "thead", "tbody", "tfoot", "tr", "th", "td", "ul", "ol", "li", "dl", "dt", "dd"
    ]
    static let alignable: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "table", "tr", "th", "td", "img"]

    mutating func html(_ source: String, block: Bool) -> String {
        var output = ""
        for token in RawHTMLToken.tokenize(source) {
            if let dropped = suppressed {
                if case .end(dropped) = token { suppressed = nil }
                continue
            }
            switch token {
            case let .text(text): output += escapeText(text)
            case let .start(name, attributes, selfClosing):
                if Self.droppedWithContent.contains(name) { if !selfClosing { suppressed = name }; continue }
                guard Self.allowedElements.contains(name) else { continue }
                let tag = element(name, attributes)
                output += tag ?? ""
                if !Self.voidElements.contains(name) { open.append((name, tag != nil)) }
            case let .end(name):
                if let index = open[floor...].lastIndex(where: { $0.name == name }) { output += close(downTo: index) }
            }
        }
        if block {
            suppressed = nil
            while open.count > floor, let last = open.last, !Self.blockContainers.contains(last.name) { output += close(downTo: open.count - 1) }
        }
        return output
    }
    mutating func close(downTo index: Int) -> String {
        var output = ""
        while open.count > index {
            let element = open.removeLast()
            if element.emitted { output += "</\(element.name)>" }
        }
        return output
    }
    /// Re-serializes an allowed start tag with only the allowlisted attributes; nil drops the tag but keeps its content.
    mutating func element(_ name: String, _ attributes: [(name: String, value: String)]) -> String? {
        var kept = ""
        func keep(_ attribute: String, _ value: String) { kept += " \(attribute)=\"\(escape(value))\"" }
        var href: String?
        for (attribute, raw) in attributes {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines), lower = value.lowercased()
            switch attribute {
            case "title": keep(attribute, raw)
            case "align" where Self.alignable.contains(name):
                if ["left", "center", "right"].contains(lower) || (lower == "justify" && name != "img")
                    || (["top", "middle", "bottom"].contains(lower) && name == "img") { keep(attribute, lower) }
            case "valign" where ["tr", "th", "td"].contains(name):
                if ["top", "middle", "bottom", "baseline"].contains(lower) { keep(attribute, lower) }
            case _ where ["width", "height"].contains(attribute) && ["img", "source", "table", "th", "td"].contains(name):
                if value.wholeMatch(of: /[0-9]{1,5}(\.[0-9]{1,3})?(%|px)?/) != nil { keep(attribute, value) }
            case _ where ["colspan", "rowspan"].contains(attribute) && ["th", "td"].contains(name):
                if let number = Int(value), (1...1000).contains(number) { keep(attribute, String(number)) }
            case "start" where name == "ol":
                if let number = Int(value), abs(number) < 1_000_000_000 { keep(attribute, String(number)) }
            case "open" where name == "details": kept += " open"
            case "href" where name == "a": href = safeDestination(value, image: false)
            case "srcset" where ["img", "source"].contains(name):
                if let srcset = safeSrcset(value) { keep(attribute, srcset) }
            case "media" where name == "source": keep(attribute, raw)
            case "type" where name == "source":
                if lower.wholeMatch(of: /image\/[a-z0-9.+-]{1,40}/) != nil { keep(attribute, lower) }
            default: break
            }
        }
        switch name {
        case "a":
            guard let href else { return nil }
            return "<a href=\"\(escape(href))\"\(kept)>"
        case "img":
            // Same resolution and notes as a Markdown image, so local, GitHub and cached sources behave alike.
            let value = { (key: String) in attributes.first { $0.name == key }?.value }
            let image = render(Markdown.Image(source: value("src")?.trimmingCharacters(in: .whitespacesAndNewlines), title: nil,
                                              [Markdown.Text(value("alt") ?? "")]))
            guard image.hasPrefix("<img ") else { return image }
            return "<img class=\"html-image\"\(kept)" + image.dropFirst(4)
        case "source":
            guard allowRelativeImages, kept.contains(" srcset=") else { return nil }
            return "<source\(kept)>"
        default: return "<\(name)\(kept)>"
        }
    }
    /// Keeps each `url [descriptor]` candidate only if its URL passes the image rules.
    func safeSrcset(_ value: String) -> String? {
        let candidates = value.split(separator: ",").compactMap { candidate -> String? in
            let parts = candidate.split(whereSeparator: \.isWhitespace).map(String.init)
            guard (1...2).contains(parts.count), let url = safeDestination(parts[0], image: true) else { return nil }
            if parts.count == 2, parts[1].wholeMatch(of: /[0-9]{1,5}(\.[0-9]{1,3})?[wx]/) == nil { return nil }
            return ([url] + parts.dropFirst()).joined(separator: " ")
        }
        return candidates.isEmpty ? nil : candidates.joined(separator: ", ")
    }
    /// Text between raw tags: keeps well-formed character references, escapes everything markup-like.
    func escapeText(_ value: String) -> String {
        value.replacing(/&(?!#[0-9]{1,7};|#[xX][0-9a-fA-F]{1,6};|[A-Za-z][A-Za-z0-9]{1,31};)/, with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
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
        // Browsers ignore surrounding spaces, so detect the scheme as they would (URLComponents rejects " javascript:").
        if let scheme = value.trimmingCharacters(in: .whitespaces).prefixMatch(of: /([A-Za-z][A-Za-z0-9+.\-]*):/)?.1 {
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
