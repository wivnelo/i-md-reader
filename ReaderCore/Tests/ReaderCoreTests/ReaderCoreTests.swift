import Foundation
import Testing
@testable import ReaderCore

@Test func rendersGFMWithoutExecutingHTML() {
    let source = """
    ---
    title: private metadata
    ---
    # 标题 *Hello*
    - [x] 已读
    - [ ] 待读

    | A | B |
    | --- | ---: |
    | 中 | 文 |

    <script>alert('unsafe')</script>

    [danger](javascript:alert(1))
    [safe](notes/下一篇.md)
    ![remote](https://example.com/a.png)

    ```swift
    let text = "<img onerror=evil()>"
    ```
    """
    let result = MarkdownRenderer().render(source)
    #expect(result.headings.count == 1)
    #expect(result.headings.first?.title == "标题 Hello")
    #expect(result.body.contains("<table>"))
    #expect(result.body.contains("checked"))
    #expect(!result.body.contains("private metadata"))
    #expect(!result.body.contains("<script>"))
    #expect(!result.body.contains("href=\"javascript:"))
    #expect(!result.body.contains("src=\"https:"))
    #expect(result.body.contains("&lt;img onerror=evil()&gt;"))
    #expect(result.body.contains("href=\"notes/下一篇.md\""))
}

@Test func preservesUnclosedFrontMatter() {
    let result = MarkdownRenderer().render("---\nnot metadata\n# Heading")
    #expect(result.body.contains("not metadata"))
}

@Test func rejectsAttributeInjection() {
    let result = MarkdownRenderer().render("[link](<file.md\"onclick=\"alert(1)>)")
    #expect(!result.body.contains("href=\"file.md\"onclick="))
}

@Test func buildsStableUniqueHeadingAnchors() {
    let result = MarkdownRenderer().render("# Hello 世界\n\n## Hello 世界\n\n## !!!")
    #expect(result.headings.map(\.id) == ["hello-世界", "hello-世界-1", "heading"])
}

@Test func blocksNetworkAndExecutableResourceDestinations() {
    let result = MarkdownRenderer().render("""
    ![escaped](<photo.png\"onerror=\"alert(1)>)
    ![absolute](//evil.example/image.png)
    ![embedded](data:image/svg+xml,evil)
    [file](file:///etc/passwd)
    [web](https://example.com)
    """)
    #expect(!result.body.contains("src=\"photo.png\"onerror="))
    #expect(!result.body.contains("src=\"//"))
    #expect(!result.body.contains("src=\"data:"))
    #expect(!result.body.contains("href=\"file:"))
    #expect(result.body.contains("href=\"https://example.com\""))
}

@Test func confinesPathsAndListsOnlyDocuments() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    try Data("# 你好".utf8).write(to: root.appendingPathComponent("note.md"))
    try Data().write(to: root.appendingPathComponent("photo.png"))
    try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root.deletingLastPathComponent())
    let children = try LocalDocuments.children(of: root, root: root)
    #expect(children.map(\.name) == ["Folder", "note.md"])
    #expect(try LocalDocuments.read(root.appendingPathComponent("note.md"), root: root) == "# 你好")
    #expect(throws: ReaderError.self) { try LocalDocuments.confined(root.appendingPathComponent("escape/secret.md"), to: root) }
    #expect(throws: ReaderError.self) { try LocalDocuments.confined(URL(fileURLWithPath: root.path + "-other/file.md"), to: root) }
}

@Test func resolvesResourcesInsideRootAcrossCanonicalAliases() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let root = base.appendingPathComponent("real")
    let alias = base.appendingPathComponent("alias")
    try fm.createDirectory(at: root.appendingPathComponent("中文目录"), withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: alias, withDestinationURL: root)
    let file = root.appendingPathComponent("中文目录/图片 名称.png")
    try Data([1, 2, 3]).write(to: file)
    #expect(try LocalDocuments.relativePath(of: file, to: alias) == "中文目录/图片 名称.png")
    #expect(try LocalDocuments.relativePath(of: root, to: alias) == "")
    var components = URLComponents()
    components.scheme = "reader-resource"; components.host = "local"
    components.path = "/中文目录/图片 名称.png"
    let url = components.url!
    let actual = try LocalDocuments.resourceURL(url, root: alias).path
    let expected = file.resolvingSymlinksInPath().path
    #expect(actual == expected)
    // Percent signs in actual filenames must not be decoded a second time.
    components.path = "/中文目录/literal%20.png"
    let literal = try LocalDocuments.resourceURL(components.url!, root: alias)
    #expect(literal.lastPathComponent == "literal%20.png")
    for invalid in ["reader-resource://local/../outside.md", "reader-resource://local/%2e%2e%2foutside.md", "reader-resource://evil/a.png", "reader-resource://user@local/a.png", "https://local/a.png"] {
        #expect(throws: ReaderError.self) { try LocalDocuments.resourceURL(URL(string: invalid)!, root: root) }
    }
}

@Test func rescansExternalChangesWithoutWritingSourceFiles() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("原文.md")
    try Data("# 初版".utf8).write(to: original)
    #expect(try LocalDocuments.children(of: root, root: root).map(\.name) == ["原文.md"])
    let renamed = root.appendingPathComponent("新版.md")
    try fm.moveItem(at: original, to: renamed)
    let changed = Data("# 外部更新\n新正文".utf8)
    try changed.write(to: renamed)
    let added = root.appendingPathComponent("新增.md")
    let extra = Data("# 新文章".utf8)
    try extra.write(to: added)
    #expect(Set(try LocalDocuments.children(of: root, root: root).map(\.name)) == ["新版.md", "新增.md"])
    #expect(try LocalDocuments.read(renamed, root: root) == "# 外部更新\n新正文")
    #expect(try Data(contentsOf: renamed) == changed)
    #expect(try Data(contentsOf: added) == extra)
    #expect(throws: (any Error).self) { try LocalDocuments.read(original, root: root) }
}
