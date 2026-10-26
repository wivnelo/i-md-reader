import Foundation
import Testing
@testable import ReaderCore
#if canImport(JavaScriptCore)
import JavaScriptCore

@Test @MainActor func bundledGrammarsAndReaderHighlightMATLABAndKeepFallbacksPlain() throws {
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ReaderApp/Resources")
    let context = try #require(JSContext())
    for name in ["highlight.min", "matlab.min"] {
        context.evaluateScript(try String(contentsOf: resources.appendingPathComponent("Vendor/\(name).js"), encoding: .utf8))
        #expect(context.exception == nil)
    }
    context.evaluateScript(#"""
    var window = this;
    window.webkit = {messageHandlers: {reader: {postMessage: function(){}}}};
    var blocks = [
      {dataset:{language:'matlab'},textContent:'% Comment\nfor k = 1:3\n disp("<script>");\nend',innerHTML:'untouched'},
      {dataset:{language:'python'},textContent:'for x in range(3): print("Hello")',innerHTML:'untouched'},
      {dataset:{language:'swift'},textContent:'let name = "Hello"',innerHTML:'untouched'},
      {dataset:{language:'unsupported-example'},textContent:'<script>do not execute</script>',innerHTML:'untouched'},
      {dataset:{language:'matlab'},textContent:'x'.repeat(20001),innerHTML:'untouched'}
    ];
    var document = {
      documentElement:{dataset:{uiLanguage:'en'}},
      querySelectorAll:function(selector){return selector === 'pre code[data-language]' ? blocks : [];}
    };
    class MutationObserver { observe(){} }
    function addEventListener(){}
    """#)
    context.evaluateScript(try String(contentsOf: resources.appendingPathComponent("reader.js"), encoding: .utf8))
    #expect(context.exception == nil)
    for index in 0..<3 {
        let html = try #require(context.evaluateScript("blocks[\(index)].innerHTML")?.toString())
        #expect(html.contains("hljs-keyword"))
        #expect(html.contains("hljs-string"))
    }
    #expect(context.evaluateScript("blocks[0].innerHTML.includes('hljs-comment')")?.toBool() == true)
    #expect(context.evaluateScript("blocks[0].innerHTML.includes('&lt;script&gt;')")?.toBool() == true)
    #expect(context.evaluateScript("blocks[3].innerHTML")?.toString() == "untouched")
    #expect(context.evaluateScript("blocks[4].innerHTML")?.toString() == "untouched")
    let rendered = MarkdownRenderer().render("```MATLAB\ndisp('<script>');\n```")
    #expect(rendered.body.contains("data-language=\"matlab\""))
    #expect(!rendered.body.contains("<script>"))
}
#endif
