import SwiftUI
import WebKit
import ReaderCore

struct ReaderWebView: UIViewRepresentable {
    let document: OpenDocument
    let fontSize: Double
    let dark: Bool
    let palette: ReaderPalette
    let language: String
    let reduceMotion: Bool
    let findRequest: Int
    @Binding var anchor: String?
    let onProgress: (Double) -> Void
    let onInternalLink: (URL) -> Void
    let onError: (String) -> Void
    let onReady: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(LocalResourceHandler(root: document.access.url, imageLoader: document.imageLoader), forURLScheme: "reader-resource")
        let bridge = WeakScriptHandler(context.coordinator)
        configuration.userContentController.add(bridge, contentWorld: .defaultClient, name: "reader")
        if let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js", subdirectory: "Vendor"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        if let url = Bundle.main.url(forResource: "reader", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isFindInteractionEnabled = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        web.allowsLinkPreview = false
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        let css = Bundle.main.url(forResource: "reader", withExtension: "css").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let theme = dark ? "dark" : "light"
        let html = """
        <!doctype html><html lang="zh-CN" data-theme="\(theme)" data-ui-language="\(language)" style="\(palette.colors(dark: dark).cssVariables)"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src reader-resource:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(css)</style></head><body style="font-size:\(fontSize)px"><article>\(document.rendered.body)</article></body></html>
        """
        var base = URLComponents()
        base.scheme = "reader-resource"; base.host = "local"
        let relativeDirectory = (try? LocalDocuments.relativePath(of: document.url.deletingLastPathComponent(), to: document.access.url)) ?? ""
        base.path = "/" + (relativeDirectory.isEmpty ? "" : relativeDirectory + "/")
        web.loadHTMLString(html, baseURL: base.url)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFindRequest != findRequest {
            context.coordinator.lastFindRequest = findRequest
            // ShowingReplace is always false: the reader never offers editing.
            web.findInteraction?.presentFindNavigator(showingReplace: false)
        }
        let appearance = "\(fontSize)-\(dark)-\(palette.rawValue)-\(language)"
        if appearance != context.coordinator.appearance {
            context.coordinator.appearance = appearance
            web.evaluateJavaScript(appearanceScript, completionHandler: nil)
        }
        if let anchor, anchor != context.coordinator.lastAnchor {
            context.coordinator.lastAnchor = anchor
            let escaped = String(data: try! JSONEncoder().encode(anchor), encoding: .utf8)!
            web.evaluateJavaScript("document.getElementById(\(escaped))?.scrollIntoView({behavior:'\(reduceMotion ? "auto" : "smooth")'});", completionHandler: nil)
            DispatchQueue.main.async { self.anchor = nil; context.coordinator.lastAnchor = nil }
        }
    }
    private var appearanceScript: String {
        let theme = dark ? "dark" : "light"
        return "document.documentElement.dataset.uiLanguage='\(language)';document.documentElement.dataset.theme='\(theme)';document.documentElement.style.cssText='\(palette.colors(dark: dark).cssVariables)';document.body.style.fontSize='\(fontSize)px';"
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.findInteraction?.dismissFindNavigator()
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "reader", contentWorld: .defaultClient)
        web.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderWebView
        var appearance: String?
        var lastFindRequest: Int
        var lastAnchor: String?
        init(_ parent: ReaderWebView) { self.parent = parent; lastFindRequest = parent.findRequest }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "progress", let value = body["value"] as? Double { parent.onProgress(value) }
            if type == "copy", let text = body["text"] as? String, text.utf8.count <= 1_048_576 { UIPasteboard.general.string = text }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A palette can change while HTML is loading; apply the latest value.
            webView.evaluateJavaScript(parent.appearanceScript, completionHandler: nil)
            parent.onReady()
            if let fragment = parent.document.url.fragment(percentEncoded: false), parent.document.rendered.headings.contains(where: { $0.id == fragment }),
               let data = try? JSONEncoder().encode(fragment), let escaped = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("document.getElementById(\(escaped))?.scrollIntoView();", completionHandler: nil)
                return
            }
            let progress = min(1, max(0, parent.document.initialProgress))
            webView.evaluateJavaScript("window.scrollTo(0, Math.max(0,document.documentElement.scrollHeight-innerHeight)*\(progress));", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onReady(); parent.onError(error.localizedDescription) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.onReady(); parent.onError(error.localizedDescription) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.onReady(); parent.onError("阅读视图已停止，请从目录重新打开文档。") }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if navigationAction.navigationType != .linkActivated {
                return url.scheme == "about" || (url.scheme == "reader-resource" && url.host == "local") ? .allow : .cancel
            }
            if url.scheme == "reader-resource", url.fragment != nil, url.path == webView.url?.path {
                return .allow
            }
            if url.scheme == "reader-resource" {
                guard !parent.document.isStandalone else {
                    parent.onError("请先添加所在文件夹，再打开相对图片或文档链接。")
                    return .cancel
                }
                do {
                    let target = try LocalDocuments.resourceURL(url, root: parent.document.access.url)
                    if LocalDocuments.markdownExtensions.contains(target.pathExtension.lowercased()) {
                        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)
                        components?.fragment = url.fragment(percentEncoded: false)
                        parent.onInternalLink(components?.url ?? target)
                    }
                    else { parent.onError("此链接不是 Markdown 文档。") }
                } catch { parent.onError(error.localizedDescription) }
            } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                _ = await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}

@MainActor private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: ReaderWebView.Coordinator?
    init(_ target: ReaderWebView.Coordinator) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor private final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    let imageLoader: (@Sendable (String) async throws -> Data)?
    init(root: URL, imageLoader: (@Sendable (String) async throws -> Data)?) {
        self.root = root; self.imageLoader = imageLoader
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        let root = self.root
        tasks[id] = Task {
            defer { tasks[id] = nil }
            do {
                guard let url = urlSchemeTask.request.url else { throw ReaderError.unsupportedFile }
                let file = try LocalDocuments.resourceURL(url, root: root)
                let mimeTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
                guard let mime = mimeTypes[file.pathExtension.lowercased()] else { throw ReaderError.unsupportedFile }
                let data: Data
                if let imageLoader {
                    let relative = try LocalDocuments.relativePath(of: file, to: root)
                    data = try await imageLoader(relative)
                } else {
                data = try await Task.detached(priority: .utility) {
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data()
                    guard data.count <= 20 * 1024 * 1024 else { throw ReaderError.tooLarge }
                    return data
                }.value
                }
                guard !Task.isCancelled else { return }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch { if !Task.isCancelled { urlSchemeTask.didFailWithError(error) } }
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id]?.cancel()
        tasks[id] = nil
    }
}
