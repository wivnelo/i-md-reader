import SwiftUI

@MainActor final class AppUpdateNotice: ObservableObject {
    @Published var available: ReleaseUpdate?
    private var checked = false
    func checkOnce() async {
        guard !checked else { return }
        checked = true
        let name = "iMDReader-9.9.9-macOS-universal.dmg"
        let url = "https://github.com/wivnelo/i-md-reader/releases/download/v9.9.9/" + name
        let payload: [String: Any] = ["tag_name": "v9.9.9", "draft": false, "prerelease": false,
                                    "assets": [["name": name, "browser_download_url": url]]]
        available = try! ReleaseUpdate.macRelease(from: JSONSerialization.data(withJSONObject: payload), currentVersion: "0.2.0")
    }
}

// The runner inserts the production `reader` view here, replacing only its
// document surface. The OpenURLAction is intercepted; no browser/download runs.
struct PromptFixture: View {
    @StateObject private var updates = AppUpdateNotice()
    @Environment(\.openURL) private var openURL
    private var locale: Locale {
        Locale(identifier: Bundle.main.object(forInfoDictionaryKey: "QALanguage") as? String ?? "en")
    }
    // PRODUCTION_READER
    var body: some View { reader.frame(width: 480, height: 180) }
}

@main struct UpdatePromptQA: App {
    var body: some Scene {
        WindowGroup("iMDReader Update Prompt QA") {
            PromptFixture().environment(\.openURL, OpenURLAction { url in
                let output = Bundle.main.object(forInfoDictionaryKey: "QAOutput") as! String
                try! (url.absoluteString + "\n").write(toFile: output, atomically: true, encoding: .utf8)
                return .handled
            })
        }
    }
}
