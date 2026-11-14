import Foundation
import Testing
@testable import ReaderCore

private func body(_ markdown: String, allowRelativeImages: Bool = true) -> String {
    MarkdownRenderer().render(markdown, allowRelativeImages: allowRelativeImages).body
}

/// The GitHub README header that was shown as a code block before.
private let readmeHeader = """
<p align="center">
  <img src="assets/nivlet-icon.png" alt="Nivlet 应用图标" width="128">
</p>

<h1 align="center">Nivlet for Mac</h1>

<p align="center">
  <strong>常用的小事，交给菜单栏。</strong><br>
  复制过的内容随时找回。
</p>

<p align="center">
  <a href="https://github.com/wivnelo/Nivlet/releases/latest"><strong>下载</strong></a> ·
  <a href="https://wivnelo.github.io/Nivlet/">官网</a> ·
  <a href="documentation/USAGE.md">使用指南</a> ·
  <a href="README.md">English</a>
</p>

<p align="center">
  <sub>免费开源 · macOS 13.0+ · Apple Silicon</sub>
</p>

<br>

<p align="center">
  <a href="docs/assets/demos/overview-zh.gif"><img src="docs/assets/demos/overview-zh.gif" alt="演示" width="720"></a><br>
  <sub>设置界面演示。</sub>
</p>

## 功能
"""

@Test func readmeHeaderRendersAsCenteredHTMLInsteadOfCode() {
    let html = body(readmeHeader)
    #expect(!html.contains("raw-html"))
    #expect(!html.contains("&lt;p"))
    #expect(!html.contains("<pre"))
    #expect(html.contains(#"<img class="html-image" width="128" src="assets/nivlet-icon.png" alt="Nivlet 应用图标" loading="lazy">"#))
    #expect(html.contains(#"<h1 align="center">Nivlet for Mac</h1>"#))
    #expect(html.contains(#"<p align="center">"#))
    #expect(html.contains("<strong>常用的小事，交给菜单栏。</strong><br>"))
    #expect(html.contains(#"<a href="https://github.com/wivnelo/Nivlet/releases/latest"><strong>下载</strong></a>"#))
    #expect(html.contains(#"<a href="documentation/USAGE.md">使用指南</a>"#))
    #expect(html.contains(#"<a href="README.md">English</a>"#))
    #expect(html.contains("<sub>免费开源 · macOS 13.0+ · Apple Silicon</sub>"))
    #expect(html.contains(#"<a href="docs/assets/demos/overview-zh.gif"><img class="html-image" width="720" src="docs/assets/demos/overview-zh.gif" alt="演示" loading="lazy"></a><br>"#))
    // Markdown after the HTML keeps its heading and table of contents entry.
    #expect(html.contains(#"<h2 id="功能">功能</h2>"#))
    #expect(MarkdownRenderer().render(readmeHeader).headings.map(\.title) == ["功能"])
    // Every raw element is closed.
    for tag in ["p", "a", "strong", "sub", "h1"] {
        #expect(html.components(separatedBy: "<\(tag)").count - 1 == html.components(separatedBy: "</\(tag)>").count - 1, "\(tag)")
    }
}

@Test func dangerousElementsAttributesAndProtocolsAreDropped() {
    let html = body("""
    <div onclick="alert(1)" style="position:fixed" class="x" id="reader-file-dates">ok</div>
    <script>alert('block')</script>
    <style>body{display:none}</style>
    <iframe src="https://example.com"></iframe><object data="x"></object><embed src="x"><form action="https://example.com"><input name="p"></form>

    <img src="x.png" onerror="alert(1)" alt="i">
    <img src="javascript:alert(1)">
    <img src="data:image/png;base64,AAAA">
    <a href="javascript:alert(1)">js</a> <a href=" javascript:alert(1)">space</a> <a href="java&#115;cript&colon;alert(1)">entity</a>
    <a href="data:text/html,<b>x</b>">data</a> <a href="vbscript:x">vb</a> <a href="/etc/passwd">abs</a>

    Inline <script>alert('inline')</script> and <b onmouseover="x">bold</b> <svg><circle/></svg>done <!-- hidden -->
    """)
    for needle in ["<script", "alert(", "<style", "display:none", "<iframe", "<object", "<embed", "<form", "<input", "onclick",
                   "onerror", "onmouseover", "style=", "class=\"x\"", "reader-file-dates", "javascript", "data:", "vbscript", "/etc/passwd",
                   "<svg", "circle", "hidden"] {
        #expect(!html.contains(needle), "\(needle)")
    }
    #expect(html.contains("<div>ok</div>"))
    #expect(html.contains(#"<img class="html-image" src="x.png" alt="i" loading="lazy">"#))
    #expect(html.components(separatedBy: #"data-reader-message="unsupported-image""#).count - 1 == 2)
    #expect(html.contains("js space entity"))
    #expect(html.contains("data vb abs"))
    #expect(html.contains("Inline  and <b>bold</b> done"))
}

@Test func relativeImagesFollowMarkdownImageRules() {
    let remote = body(#"<img src="https://example.com/badge.svg" alt="badge">"#)
    #expect(remote == #"<span class="resource-note" data-reader-message="unsupported-image">暂不支持此图片地址</span>"# + "\n")
    #expect(body("![badge](https://example.com/badge.svg)") == "<p>\(remote.dropLast())</p>")
    #expect(body(#"<p><img src="local.gif"></p>"#, allowRelativeImages: false).contains(#"data-reader-message="folder-access""#))
    let picture = body("""
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png 1x, https://x.example/a.png 2x, logo@2x.png 2x">
      <source srcset="javascript:alert(1)">
      <img src="logo.png" srcset="logo.png 1x, logo@2x.png 2x" alt="logo" width="50%" height="9e9">
    </picture>
    """)
    #expect(picture.contains(#"<source media="(prefers-color-scheme: dark)" srcset="logo-dark.png 1x, logo@2x.png 2x">"#))
    #expect(picture.contains(#"<img class="html-image" srcset="logo.png 1x, logo@2x.png 2x" width="50%" src="logo.png" alt="logo" loading="lazy">"#))
    #expect(!picture.contains("javascript"))
    #expect(!picture.contains("9e9"))
    #expect(picture.hasSuffix("</picture>\n"))
}

@Test func containersSpanMarkdownBlocksWithoutLeakingOutOfScope() {
    let details = body("""
    <details open>
    <summary>More</summary>

    Hidden **text**.

    </details>

    <div align="center">

    # Title

    </div>
    """)
    #expect(details.hasPrefix("<details open>\n<summary>More</summary>\n<p>Hidden <strong>text</strong>.</p></details>"))
    #expect(details.contains(#"<div align="center">"# + "\n" + #"<h1 id="title">Title</h1></div>"#))
    // An unclosed inline tag ends with its paragraph; stray end tags cannot close the reader's own markup.
    let stray = body("a <b>bold\n\nnext </p></div></article> <i>x</i>\n\n> quote <sub>s\n\n<span>open block")
    #expect(stray.contains("<p>a <b>bold</b></p>"))
    #expect(stray.contains("<p>next  <i>x</i></p>"))
    #expect(stray.contains("<blockquote><p>quote <sub>s</sub></p></blockquote>"))
    #expect(stray.hasSuffix("<p><span>open block</span></p>"))
    #expect(!stray.contains("</article>") && !stray.contains("</div>"))
    let table = body("| a |\n| - |\n| x <b>y |\n\n<table><tr><td colspan=\"2\" valign=\"top\" onclick=\"x\">c</td></tr></table>")
    #expect(table.contains("<td>x <b>y</b></td>"))
    #expect(table.contains(#"<table><tr><td colspan="2" valign="top">c</td></tr></table>"#))
}

@Test func textAndEntitiesStayInert() {
    let html = body("<p>&copy; 2026 &amp; R&D &lt;b&gt; <em>x</em> &#x3C;script&#62; 1 < 2 > 0</p>")
    #expect(html.contains("&copy; 2026 &amp; R&amp;D &lt;b&gt; <em>x</em> &#x3C;script&#62; 1 &lt; 2 &gt; 0"))
    #expect(RawHTMLToken.decodeReferences("a&amp;b&#58;&#x3a;&colon;&unknown;&") == "a&b:::&unknown;&")
    #expect(RawHTMLToken.tokenize("<a href='x' title=t>y</a><!--c--><br/>") == [
        .start(name: "a", attributes: [("href", "x"), ("title", "t")], selfClosing: false), .text("y"), .end("a"),
        .start(name: "br", attributes: [], selfClosing: true)
    ])
    #expect(RawHTMLToken.tokenize("<a href=\"unterminated>text") == [.text("<a href=\"unterminated>text")])
}
