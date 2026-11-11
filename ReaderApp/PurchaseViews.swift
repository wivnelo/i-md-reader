#if os(iOS)
import ReaderCore
import SwiftUI

struct PurchaseSheet: View {
    @ObservedObject private var store = PurchaseStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // TODO: Boss 确定付费范围后再添加解锁内容说明。
                    if store.isUnlocked {
                        Text("已解锁")
                    } else {
                        LabeledContent("价格") {
                            if let product = store.product {
                                Text(verbatim: product.displayPrice)
                            } else if store.isBusy {
                                Text("正在载入…")
                            } else {
                                Text(verbatim: "—")
                            }
                        }
                        Button("购买") { Task { await store.purchase() } }
                            .disabled(store.product == nil || store.isBusy)
                    }
                    Button("恢复购买") { Task { await store.restore() } }
                        .disabled(store.isBusy)
                    if let message = store.message {
                        switch message {
                        case .productUnavailable: Text("暂时无法获取商品信息，请稍后重试。")
                        case .pending: Text("购买正在等待批准。")
                        case .unverified: Text("无法验证这次购买，请稍后重试。")
                        case .purchaseFailed: Text("购买未完成，请稍后重试。")
                        case .restored: Text("已恢复购买。")
                        case .nothingToRestore: Text("没有可恢复的购买。")
                        case .restoreFailed: Text("恢复购买失败，请稍后重试。")
                        }
                    }
                } footer: {
                    Text("一次购买，永久使用，iPhone 和 iPad 通用。付款由 Apple 处理，iMDReader 不接收支付信息。")
                }
            }
            .navigationTitle(ReaderLanguage.message("解锁 iMDReader", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { if store.product == nil { await store.loadProduct() } }
    }
}

struct PurchaseEntryModifier: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject private var store = PurchaseStore.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        if PremiumAccess.showsPurchaseEntry(config: store.config) {
            content
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refreshEntitlements() } }
                }
                .sheet(isPresented: $isPresented) { PurchaseSheet() }
        } else {
            content
        }
    }
}

extension View {
    func purchaseEntry(isPresented: Binding<Bool>) -> some View {
        modifier(PurchaseEntryModifier(isPresented: isPresented))
    }
}
#endif
