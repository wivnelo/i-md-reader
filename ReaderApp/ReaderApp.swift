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
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开 Markdown 文件") { actions?.openFile() }.keyboardShortcut("o")
            Button("添加本地文件夹") { actions?.openFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("添加 GitHub 来源") { actions?.addGitHub() }
        }
        CommandGroup(after: .textEditing) {
            Button("文内查找") { actions?.find() }.keyboardShortcut("f")
        }
    }
}
#endif
