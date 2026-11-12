#if os(iOS)
import Combine
import ReaderCore
import SwiftUI

/// Used in the existing settings menu; observing here keeps its remaining days current.
struct PurchaseMenuEntry: View {
    @Binding var isPresented: Bool
    @ObservedObject private var store = PurchaseStore.shared
    var body: some View {
        if store.config.isEnabled {
            Button { isPresented = true } label: {
                if let days = store.access.remainingDays {
                    Text("试用剩余 \(Int64(days)) 天")
                } else if store.access == .unlockedLifetime { Label("已解锁", systemImage: "lock.open") }
                else { Label("试用与购买", systemImage: "lock.open") }
            }
            Link("使用支持", destination: URL(string: "https://wivnelo.github.io/i-md-reader/support.html")!)
        }
    }
}


struct PurchaseEntryModifier: ViewModifier {
    @Binding var isPresented: Bool
    let openGitHub: () -> Void
    let openSync: () -> Void
    let openCache: () -> Void
    var storeSources: ReaderStore?
    var onUnlocked: () -> Void = {}
    @ObservedObject private var store = PurchaseStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    @State private var managingSources = false
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        if store.config.isEnabled {
            content
                .overlay {
                    if !store.isUnlocked {
                        PurchaseSheet(onManageSources: { managingSources = true }) {
                            lockedSettingsMenu
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let days = store.access.remainingDays, days <= 3 {
                        Button { isPresented = true } label: {
                            Text("试用剩余 \(Int64(days)) 天")
                        }.padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
                .task { await store.start() }
                .onChange(of: store.access) { previous, access in
                    if access.isUnlocked {
                        if !previous.isUnlocked { isPresented = false }
                        onUnlocked()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refreshEntitlements() } }
                }
                .task(id: store.access) {
                    if case .trial(_, let end, _) = store.access {
                        do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
                        catch { return }
                        store.updateClock()
                    }
                }
                .onReceive(timer) { _ in store.updateClock() }
                .sheet(isPresented: Binding(
                    get: { isPresented && store.isUnlocked },
                    set: { isPresented = $0 }
                )) { PurchaseSheet() }
                .sheet(isPresented: $managingSources) {
                    if let storeSources {
                        LockedSourceManager(store: storeSources)
                    }
                }
        } else { content }
    }

    private var lockedSettingsMenu: some View {
        Menu {
            Button("GitHub 授权", action: openGitHub)
            Button("iCloud 同步", action: openSync)
            Button("离线缓存", action: openCache)
            if storeSources != nil {
                Button("管理来源") { managingSources = true }
            }
            Picker("语言", selection: $languageValue) {
                ForEach(ReaderLanguage.allCases) { item in
                    Text(languageTitle(item)).tag(item.rawValue)
                }
            }
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                Text("版本 \(version)（\(build)）")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .padding(8).frame(minWidth: 44, minHeight: 44)
                .background {
                    Circle().fill(ReaderPalette.mist.colors(dark: colorScheme == .dark).selection.opacity(0.5))
                        .aspectRatio(1, contentMode: .fill)
                }
        }
        .accessibilityLabel("应用设置")
        .accessibilityIdentifier("paywall.settings")
    }

    private func languageTitle(_ language: ReaderLanguage) -> String {
        // Switch on rawValue so this compiles both on this branch
        // (system/zh-Hans/en) and on integration (also zh-Hant/ja/ko).
        switch language.rawValue {
        case "zh-Hans": "简体中文"
        case "en": "English"
        case "zh-Hant": "繁體中文"
        case "ja": "日本語"
        case "ko": "한국어"
        default: "跟随系统"
        }
    }
}

private struct LockedSourceManager: View {
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sources) { source in
                    HStack {
                        Text(verbatim: source.name)
                        Spacer()
                        Button("移除来源", role: .destructive) { store.remove(source) }
                    }
                }
            }
            .navigationTitle("管理来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") } } }
        }
    }
}

private struct PurchaseContentLockModifier: ViewModifier {
    @ObservedObject private var store = PurchaseStore.shared
    func body(content: Content) -> some View {
        content
            .disabled(!store.isUnlocked)
            .opacity(store.isUnlocked ? 1 : 0)
            .allowsHitTesting(store.isUnlocked)
            .accessibilityHidden(!store.isUnlocked)
    }
}

extension View {
    // Applied before the existing sheets so settings remain interactive while locked.
    func purchaseContentLock() -> some View { modifier(PurchaseContentLockModifier()) }

    func purchaseEntry(isPresented: Binding<Bool>, openGitHub: @escaping () -> Void,
                       openSync: @escaping () -> Void, openCache: @escaping () -> Void,
                       storeSources: ReaderStore? = nil, onUnlocked: @escaping () -> Void = {}) -> some View {
        modifier(PurchaseEntryModifier(isPresented: isPresented, openGitHub: openGitHub,
                                       openSync: openSync, openCache: openCache,
                                       storeSources: storeSources, onUnlocked: onUnlocked))
    }
}
#endif
