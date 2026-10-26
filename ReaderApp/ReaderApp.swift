import SwiftUI

@main struct iMDReaderApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("iMDReader", id: "reader") {
            ReaderScreen().frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 760)
        .commands { ReaderCommands() }
        #else
        WindowGroup { ReaderScreen() }
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
