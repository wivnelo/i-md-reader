import Foundation
import Testing
@testable import ReaderCore

@Test func classifiesMarkdownCodeTextAndUnknownFiles() {
    #expect(ReadableFile.kind(named: "Notes.MD") == .markdown)
    #expect(ReadableFile.kind(named: "App.swift") == .code(grammar: "swift", label: "Swift"))
    #expect(ReadableFile.kind(named: "index.tsx") == .code(grammar: "typescript", label: "TypeScript"))
    #expect(ReadableFile.kind(named: "Cargo.toml") == .code(grammar: "ini", label: "TOML"))
    #expect(ReadableFile.kind(named: "Info.plist") == .code(grammar: "xml", label: "XML"))
    #expect(ReadableFile.kind(named: "notes.txt") == .code(grammar: nil, label: "TXT"))
    #expect(ReadableFile.kind(named: "Makefile") == .code(grammar: "makefile", label: "Makefile"))
    #expect(ReadableFile.kind(named: "LICENSE") == .code(grammar: nil, label: "LICENSE"))
    #expect(ReadableFile.kind(named: "photo.png") == nil)
    #expect(ReadableFile.kind(named: "archive.zip") == nil)
    #expect(ReadableFile.kind(named: "unknownname") == nil)
    #expect(ReadableFile.allExtensions.contains("md") && ReadableFile.allExtensions.contains("py"))
}

@Test func rendersSourceAsOneEscapedNumberedBlockWithoutExecutingIt() {
    let source = "let a = \"<script>alert(1)</script>\"\r\nif a < b && c > d {\n}\n"
    let result = ReadableFile.render(source, name: "Main.swift")
    #expect(result.headings.isEmpty)
    #expect(result.body.contains("class=\"codeblock codefile\""))
    #expect(result.body.contains("<span>Swift</span>"))
    #expect(result.body.contains("data-language=\"swift\""))
    #expect(result.body.contains("<pre class=\"gutter\" aria-hidden=\"true\">1\n2\n3</pre>"))
    #expect(result.body.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    #expect(result.body.contains("a &lt; b &amp;&amp; c &gt; d"))
    #expect(!result.body.contains("<script>"))
    #expect(!result.body.contains("\r"))
}

@Test func plainTextHasNoGrammarAndEmptyFileStillHasOneLine() {
    let text = ReadableFile.render("hello", name: "README")
    #expect(!text.body.contains("data-language"))
    #expect(text.body.contains("<span>README</span>"))
    let empty = ReadableFile.render("", name: "empty.py")
    #expect(empty.body.contains("<pre class=\"gutter\" aria-hidden=\"true\">1</pre>"))
}

@Test func markdownKeepsTheMarkdownRenderer() {
    let result = ReadableFile.render("# Title\n\nBody", name: "doc.md")
    #expect(result.headings.first?.title == "Title")
    #expect(!result.body.contains("codefile"))
}

@Test func readsCodeFilesWithBinaryAndSizeGuards() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let code = root.appendingPathComponent("main.py")
    try Data("print('你好')\n".utf8).write(to: code)
    #expect(try LocalDocuments.read(code, root: root) == "print('你好')\n")

    let binary = root.appendingPathComponent("blob.json")
    try Data([0x7b, 0x00, 0x7d]).write(to: binary)
    #expect(throws: ReaderError.notText) { try LocalDocuments.read(binary, root: root) }

    let utf16 = root.appendingPathComponent("wide.txt")
    try "宽字符".data(using: .utf16)!.write(to: utf16)
    #expect(try LocalDocuments.read(utf16, root: root) == "宽字符")

    let large = root.appendingPathComponent("big.js")
    try Data(repeating: 0x61, count: ReadableFile.codeSizeLimit + 1).write(to: large)
    #expect(throws: ReaderError.codeTooLarge) { try LocalDocuments.read(large, root: root) }

    let unknown = root.appendingPathComponent("image.png")
    try Data([0x89, 0x50]).write(to: unknown)
    #expect(throws: ReaderError.unsupportedFile) { try LocalDocuments.read(unknown, root: root) }
}

@Test func fileNodesMarkCodeFilesReadable() {
    let root = URL(fileURLWithPath: "/tmp/x")
    #expect(FileNode(url: root.appendingPathComponent("a.go"), isDirectory: false).isReadable)
    #expect(!FileNode(url: root.appendingPathComponent("a.go"), isDirectory: false).isMarkdown)
    #expect(!FileNode(url: root.appendingPathComponent("a.bin"), isDirectory: false).isReadable)
    #expect(!FileNode(url: root.appendingPathComponent("src"), isDirectory: true).isReadable)
}
