import AppKit
import WebKit

@MainActor private final class Checks: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    struct Case {
        let width: CGFloat
        let language: String
        let dark: Bool
        let committed: Bool
        let empty: Bool
    }
    let resources = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    var cases: [Case] = []
    var index = 0
    var screenshots = 0
    let web: WKWebView
    var labels: [String] = []
    var copied = ""

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 390, height: 700), configuration: config)
        super.init()
        web.navigationDelegate = self
        config.userContentController.add(self, contentWorld: .defaultClient, name: "reader")
        let script = try! String(contentsOf: resources.appendingPathComponent("reader.js"), encoding: .utf8)
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        for width: CGFloat in [320, 390, 768, 1100] {
            for language in ["en", "zh-Hans"] {
                for dark in [false, true] {
                    for committed in [false, true] {
                        for empty in [false, true] {
                            cases.append(Case(width: width, language: language, dark: dark, committed: committed, empty: empty))
                        }
                    }
                }
            }
        }
    }
    func fail(_ message: String) -> Never { fatalError("FAIL case \(index): \(message)") }
    func run() {
        let item = cases[index]
        web.setFrameSize(NSSize(width: item.width, height: 700))
        let css = try! String(contentsOf: resources.appendingPathComponent("reader.css"), encoding: .utf8)
        let notes = "<p><span class='resource-note' data-reader-message='folder-access'>图片需要所在文件夹的访问权限</span></p><p><span class='resource-note' data-reader-message='unsupported-image'>暂不支持此图片地址</span></p>"
        let body = item.empty ? "" : "<h1>Reading Notes 阅读笔记</h1>\(notes)<section class='codeblock'><header><span>Swift</span><button class='copy' type='button'>复制</button></header><pre><code>let number = 42</code></pre></section><div id='reading-anchor'>Keep this reading position</div>" + String(repeating: "<p>Long document reading position fixture.</p>", count: 70)
        web.loadHTMLString("""
        <html data-ui-language="\(item.language)" data-theme="\(item.dark ? "dark" : "light")"><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'"><style>\(css)</style></head><body style="font-size:17px"><article><div id="reader-file-dates" class="file-dates" hidden></div>\(body)</article></body></html>
        """, baseURL: nil)
    }
    func evaluate(_ script: String) async throws -> Any? { try await web.evaluateJavaScript(script) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do { try await verify() }
            catch { fail(error.localizedDescription) }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any], body["type"] as? String == "copy", let text = body["text"] as? String { copied = text }
    }
    func verify() async throws {
        let item = cases[index]
        let date = Date(timeIntervalSince1970: 1_793_165_400)
        let dates = item.committed ? DocumentDates(committed: date) : DocumentDates(modified: date)
        labels = dates.labels(language: item.language)
        if !item.empty {
            _ = try await evaluate("window.scrollTo(0,400);")
            for _ in 0..<100 {
                if (try await evaluate("window.scrollY") as? Double ?? 0) >= 399 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            _ = try await evaluate("window.beforeScroll=window.scrollY;window.beforeY=document.getElementById('reading-anchor').getBoundingClientRect().top;")
        }
        let fixture = DateScriptFixture(document: .init(dates: dates), language: item.language)
        _ = try await evaluate(fixture.datesScript)
        try await Task.sleep(for: .milliseconds(30)) // Let WebKit commit the requested scroll offset.
        let state = try await evaluate("({hidden:document.getElementById('reader-file-dates').hidden,dates:document.getElementById('reader-file-dates').innerText,overflow:document.documentElement.scrollWidth>innerWidth})") as? [String: Any]
        guard state?["hidden"] as? Bool == false, state?["dates"] as? String == labels[0], state?["overflow"] as? Bool == false else { fail("date visibility/label/overflow \(String(describing: state))") }
        if !item.empty {
            let delta = try await evaluate("Math.abs(document.getElementById('reading-anchor').getBoundingClientRect().top-window.beforeY)") as? Double
            guard let delta, delta < 1 else {
                let metrics = try await evaluate("JSON.stringify({beforeY:window.beforeY,beforeScroll:window.beforeScroll,scroll:window.scrollY,afterY:document.getElementById('reading-anchor').getBoundingClientRect().top,height:innerHeight})")
                FileHandle.standardError.write(Data("SCROLL \(String(describing: metrics))\n".utf8))
                fail("reading position changed by \(String(describing: delta))")
            }
            // Exercise the actual isolated reader script through DOM mutations.
            for language in ["en", "zh-Hans", "en", item.language] {
                _ = try await evaluate("document.documentElement.dataset.uiLanguage='\(language)';")
                let notes = try await evaluate("Array.from(document.querySelectorAll('.resource-note')).map(x=>x.textContent)") as? [String]
                let expected = language == "en" ? ["Images require access to their containing folder", "This image address is not supported yet"] : ["图片需要所在文件夹的访问权限", "暂不支持此图片地址"]
                guard notes == expected else { fail("resource language \(language): \(String(describing: notes))") }
            }
            _ = try await evaluate("document.querySelector('.copy').click();")
            for _ in 0..<100 where copied.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
            guard copied == "let number = 42" else { fail("isolated copy bridge") }
            copied = ""
            _ = try await evaluate("window.scrollTo(0,0);")
        }
        if index == 0 || index == 1 || index == 12 || index == 13 {
            let image = try await web.takeSnapshot(configuration: nil)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fail("snapshot") }
            try png.write(to: output.appendingPathComponent("webview-\(index).png"))
            screenshots += 1
        }
        // Missing dates still remain absent, including an empty body.
        let absent = DateScriptFixture(document: .init(dates: DocumentDates()), language: item.language)
        _ = try await evaluate(absent.datesScript)
        guard try await evaluate("document.getElementById('reader-file-dates').hidden") as? Bool == true else { fail("missing date shown") }
        print("PASS \(index): width=\(Int(item.width)) language=\(item.language) dark=\(item.dark) committed=\(item.committed) empty=\(item.empty)")
        index += 1
        if index < cases.count { run() }
        else {
            print("PASS: \(cases.count) WebKit combinations; empty/nonempty dates, missing metadata, scroll preservation, language round trips and copy bridge; \(screenshots) snapshots.")
            NSApplication.shared.terminate(nil)
        }
    }
}

@main private struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let checks = Checks()
        checks.run()
        app.run()
    }
}
