import Foundation

/// What a library file opens as: Markdown, or source/plain text shown read-only with line numbers.
public enum ReadableKind: Equatable, Sendable {
    case markdown
    /// `grammar` is a bundled highlight.js language id; nil shows plain text.
    case code(grammar: String?, label: String)
}

/// File-type table only (no Markdown dependency) so standalone checks can compile it.
public enum ReadableFile {
    /// Source files above this size are refused; highlighting stops far earlier (see reader.js).
    public static let codeSizeLimit = 2 * 1_024 * 1_024

    public static func kind(of url: URL) -> ReadableKind? { kind(named: url.lastPathComponent) }

    public static func kind(named name: String) -> ReadableKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if LocalDocuments.markdownExtensions.contains(ext) { return .markdown }
        if ext.isEmpty {
            guard let match = wholeNames[name.lowercased()] else { return nil }
            return .code(grammar: match.grammar, label: match.label)
        }
        guard let match = extensions[ext] else { return nil }
        return .code(grammar: match.grammar, label: match.label)
    }

    /// Every recognized filename extension, for building a file-picker filter.
    public static var allExtensions: [String] { Array(LocalDocuments.markdownExtensions) + extensions.keys.sorted() }

    public static func isReadable(_ url: URL) -> Bool { kind(of: url) != nil }
    public static func isReadable(named name: String) -> Bool { kind(named: name) != nil }

    /// Extension → (highlight.js grammar in the bundled common build, label shown on the file header).
    private static let extensions: [String: (grammar: String?, label: String)] = {
        var map: [String: (grammar: String?, label: String)] = [:]
        func add(_ grammar: String?, _ label: String, _ names: String) {
            for name in names.split(separator: " ") { map[String(name)] = (grammar, label) }
        }
        add("swift", "Swift", "swift")
        add("objectivec", "Objective-C", "m mm")
        add("c", "C", "c")
        add("cpp", "C++", "cc cpp cxx hpp hh hxx h")
        add("csharp", "C#", "cs")
        add("java", "Java", "java")
        add("kotlin", "Kotlin", "kt kts")
        add("go", "Go", "go")
        add("rust", "Rust", "rs")
        add("python", "Python", "py pyi pyw")
        add("ruby", "Ruby", "rb rake gemspec")
        add("php", "PHP", "php")
        add("perl", "Perl", "pl pm")
        add("lua", "Lua", "lua")
        add("r", "R", "r")
        add("javascript", "JavaScript", "js mjs cjs jsx")
        add("typescript", "TypeScript", "ts mts cts tsx")
        add("css", "CSS", "css")
        add("scss", "SCSS", "scss")
        add("less", "Less", "less")
        add("xml", "HTML", "html htm xhtml")
        add("xml", "XML", "xml svg plist xsd xsl storyboard xib entitlements")
        add("json", "JSON", "json jsonc geojson webmanifest")
        add("yaml", "YAML", "yaml yml")
        add("ini", "TOML", "toml")
        add("ini", "INI", "ini cfg conf properties")
        add("shell", "Shell", "sh bash zsh fish command")
        add("sql", "SQL", "sql")
        add("graphql", "GraphQL", "graphql gql")
        add("diff", "Diff", "diff patch")
        add("makefile", "Makefile", "mk mak")
        add("vbnet", "VB.NET", "vb")
        add(nil, "TXT", "txt text")
        add(nil, "LOG", "log")
        add(nil, "CSV", "csv")
        add(nil, "TSV", "tsv")
        return map
    }()

    /// Common extensionless files, matched case-insensitively.
    private static let wholeNames: [String: (grammar: String?, label: String)] = [
        "makefile": ("makefile", "Makefile"), "gnumakefile": ("makefile", "Makefile"),
        "dockerfile": (nil, "Dockerfile"), "gemfile": ("ruby", "Ruby"), "podfile": ("ruby", "Ruby"),
        "rakefile": ("ruby", "Ruby"), "brewfile": ("ruby", "Ruby"),
        "license": (nil, "LICENSE"), "licence": (nil, "LICENSE"), "copying": (nil, "COPYING"),
        "readme": (nil, "README"), "authors": (nil, "AUTHORS"), "changelog": (nil, "CHANGELOG"), "notice": (nil, "NOTICE")
    ]
}
