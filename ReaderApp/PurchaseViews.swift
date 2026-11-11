#if os(iOS)
import ReaderCore
import SwiftUI

struct PurchaseSheet: View {
    @ObservedObject private var store = PurchaseStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.access == .unlockedLifetime {
                        Text("已解锁")
                    } else {
                        if store.access == .lockedExpired {
                            Text("14 天试用已到期，请购买永久解锁以继续使用。")
                        } else {
                            Text("免费试用全部功能 14 天。到期后无法打开文档或继续使用全部功能，需购买永久解锁。")
                        }
                        if let days = store.access.remainingDays {
                            Text("试用剩余 \(Int64(days)) 天")
                        }
                        LabeledContent("价格") {
                            if let product = store.product { Text(verbatim: product.displayPrice) }
                            else if store.isBusy { Text("正在载入…") }
                            else { Text(verbatim: "—") }
                        }
                        if store.access == .lockedNotStarted {
                            Button("开始 14 天试用") { Task { await store.purchase(trial: true) } }
                                .disabled(store.trialProduct == nil || store.isBusy)
                        }
                        Button("购买永久解锁") { Task { await store.purchase() } }
                            .disabled(store.product == nil || store.isBusy)
                    }
                    Button("恢复购买") { Task { await store.restore() } }.disabled(store.isBusy)
                    if let message = store.message {
                        switch message {
                        case .productUnavailable: Text("暂时无法获取商品信息，请稍后重试。")
                        case .pending: Text("购买正在等待批准。")
                        case .unverified: Text("无法验证这次购买，请稍后重试。")
                        case .purchaseFailed: Text("购买未完成，请稍后重试。")
                        case .restored: Text("已恢复购买。")
                        case .nothingToRestore: Text("没有可恢复的购买。")
                        case .restoreFailed: Text("恢复购买失败，请稍后重试。")
                        case .cancelled: Text("操作已取消。")
                        }
                    }
                } footer: {
                    Text("一次购买，永久使用，iPhone 和 iPad 通用。付款由 Apple 处理，iMDReader 不接收支付信息。")
                }
                Section { PurchaseLinks() }
            }
            .navigationTitle("试用与购买")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") } } }
        }
        .task { if store.product == nil || store.trialProduct == nil { await store.loadProduct() } }
    }
}

private struct PurchaseLinks: View {
    var body: some View {
        Link("隐私政策", destination: URL(string: "https://wivnelo.github.io/i-md-reader/privacy.html")!)
        Link("使用支持", destination: URL(string: "https://wivnelo.github.io/i-md-reader/support.html")!)
    }
}

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
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    @State private var managingSources = false
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        if store.config.isEnabled {
            content
                .overlay {
                    if !store.isUnlocked {
                        ScrollView {
                            VStack(spacing: 20) {
                                if store.access == .lockedExpired {
                                    Text("14 天试用已到期，请购买永久解锁以继续使用。")
                                } else {
                                    Text("免费试用全部功能 14 天。到期后无法打开文档或继续使用全部功能，需购买永久解锁。")
                                }
                                Button("试用与购买") { isPresented = true }
                                Menu("应用设置") {
                                    Button("GitHub 授权", action: openGitHub)
                                    Button("iCloud 同步", action: openSync)
                                    Button("离线缓存", action: openCache)
                                    if storeSources != nil {
                                        Button("管理来源") { managingSources = true }
                                    }
                                }
                                Picker("语言", selection: $languageValue) {
                                    ForEach(ReaderLanguage.allCases) { item in
                                        Text(languageTitle(item)).tag(item.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .accessibilityLabel("语言")
                                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                   let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                                    Text("版本 \(version)（\(build)）")
                                }
                                PurchaseLinks()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let days = store.access.remainingDays, days <= 3 {
                        Button { isPresented = true } label: {
                            Text("试用剩余 \(Int64(days)) 天")
                        }.padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
                .task {
                    await store.start()
                    presentIfLocked()
                }
                .onChange(of: store.hasRefreshed) { _, _ in presentIfLocked() }
                .onChange(of: store.access) { _, access in
                    presentIfLocked()
                    if access.isUnlocked { onUnlocked() }
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
                .sheet(isPresented: $isPresented) { PurchaseSheet() }
                .sheet(isPresented: $managingSources) {
                    if let storeSources {
                        LockedSourceManager(store: storeSources)
                    }
                }
        } else { content }
    }

    private func presentIfLocked() {
        if store.hasRefreshed && !store.isUnlocked { isPresented = true }
    }

    private func languageTitle(_ language: ReaderLanguage) -> String {
        switch language {
        case .system: "跟随系统"
        case .chinese: "简体中文"
        case .english: "English"
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
