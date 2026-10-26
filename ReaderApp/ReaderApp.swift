import SwiftUI
import ReaderCore

@main struct iMDReaderApp: App {
    @StateObject private var updates = AppUpdateNotice()
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    @Environment(\.openURL) private var openURL
    private var locale: Locale { (ReaderLanguage(rawValue: languageValue) ?? .system).locale }
    private var reader: some View {
        ReaderScreen()
            .task { await updates.checkOnce() }
            .alert(ReaderLanguage.message("发现新版本", locale: locale), isPresented: Binding(
                get: { updates.available != nil }, set: { if !$0 { updates.available = nil } }
            ), presenting: updates.available) { update in
                Button(ReaderLanguage.message("下载更新", locale: locale)) {
                    openURL(update.downloadURL)
                }
                Button(ReaderLanguage.message("稍后", locale: locale), role: .cancel) {}
            } message: { update in
                Text(ReaderLanguage.message("新版本可供下载，下载后请手动安装。", locale: locale))
                Text(update.version)
            }
    }
    var body: some Scene {
        #if os(macOS)
        Window("iMDReader", id: "reader") {
            reader.frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 760)
        .commands { ReaderCommands() }
        #else
        WindowGroup { reader }
        #endif
    }
}

#if os(macOS)
struct ReaderActions {
    let openFile: () -> Void
    let openFolder: () -> Void
    let addGitHub: () -> Void
    let find: () -> Void
}
private struct ReaderActionsKey: FocusedValueKey { typealias Value = ReaderActions }
extension FocusedValues {
    var readerActions: ReaderActions? {
        get { self[ReaderActionsKey.self] }
        set { self[ReaderActionsKey.self] = newValue }
    }
}
private struct ReaderCommands: Commands {
    @FocusedValue(\.readerActions) private var actions
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    private var locale: Locale { (ReaderLanguage(rawValue: languageValue) ?? .system).locale }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button { actions?.openFile() } label: { Text(verbatim: ReaderLanguage.message("打开 Markdown 文件", locale: locale)) }.keyboardShortcut("o")
            Button { actions?.openFolder() } label: { Text(verbatim: ReaderLanguage.message("添加本地文件夹", locale: locale)) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button { actions?.addGitHub() } label: { Text(verbatim: ReaderLanguage.message("添加 GitHub 来源", locale: locale)) }
        }
        CommandGroup(after: .textEditing) {
            Button { actions?.find() } label: { Text(verbatim: ReaderLanguage.message("文内查找", locale: locale)) }.keyboardShortcut("f")
        }
    }
}
#endif

@MainActor private final class AppUpdateNotice: ObservableObject {
    @Published var available: ReleaseUpdate?
    private let checker = StartupUpdateCheck()
    func checkOnce() async {
        #if os(macOS)
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return }
        if let update = await checker.checkMac(currentVersion: version) { available = update }
        #else
        // Mobile builds currently use local development signing, with no public
        // App Store/TestFlight channel. Never offer Mac assets to iOS users.
        #endif
    }
}
