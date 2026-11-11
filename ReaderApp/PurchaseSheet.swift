#if os(iOS)
import ReaderCore
import SwiftUI

struct PurchaseSheet<HeaderActions: View>: View {
    @ObservedObject var store: PurchaseStore = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let headerActions: HeaderActions?
    private let onManageSources: (() -> Void)?

    init(store: PurchaseStore = .shared) where HeaderActions == EmptyView {
        self.store = store
        self.headerActions = nil
        self.onManageSources = nil
    }

    init(store: PurchaseStore = .shared, onManageSources: @escaping () -> Void,
         @ViewBuilder headerActions: () -> HeaderActions) {
        self.store = store
        self.headerActions = headerActions()
        self.onManageSources = onManageSources
    }

    private var colors: ReaderColors { ReaderPalette.mist.colors(dark: colorScheme == .dark) }
    private var needsProducts: Bool { store.product == nil || store.trialProduct == nil }
    private var unavailable: Bool { store.product == nil && !store.isLoadingProducts }
    private var trialUnavailable: Bool { store.product != nil && store.trialProduct == nil && !store.isLoadingProducts }
    private var waitingTitle: LocalizedStringKey? {
        switch store.operation {
        case .purchasing: "正在与 App Store 通信…"
        case .restoring: "正在恢复购买…"
        case .verifying: "正在验证购买…"
        case nil: store.message == .pending ? "等待批准" : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("ReaderBrand")
                    .resizable().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(verbatim: "iMDReader").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if let headerActions {
                    headerActions
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(colors.selection.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("关闭购买页，返回资料管理")
                    .accessibilityIdentifier("paywall.close")
                }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 650)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    VStack(alignment: .leading, spacing: 14) {
                        benefit("本地文件、文件夹与 GitHub 阅读")
                        benefit("离线阅读与 iCloud 阅读位置同步")
                        benefit("iPhone 与 iPad 通用，买断支持家庭共享")
                    }
                    .font(.subheadline)
                    if store.access != .unlockedLifetime { price }
                    feedback
                    actions
                    if store.access != .unlockedLifetime {
                        Text("试用不会自动扣费。14 天后需购买永久解锁，才能继续打开文档；你的文件与资料库会保留。")
                            .font(.footnote).foregroundStyle(colors.secondary)
                            .multilineTextAlignment(.center)
                    }
                    footer
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 24)
                .frame(maxWidth: 488)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("paywall.content")
        }
        .foregroundStyle(colors.ink)
        .tint(colors.accent)
        .background(colors.paper)
        .presentationBackground(colors.paper)
        .task { if store.access != .unlockedLifetime && needsProducts { await store.loadProduct() } }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let days = store.access.remainingDays, waitingTitle == nil {
                Text("试用剩余 \(Int64(days)) 天").font(.subheadline.weight(.semibold)).foregroundStyle(colors.accent)
            } else {
                Text(eyebrow).font(.subheadline.weight(.semibold)).foregroundStyle(colors.accent)
            }
            Text(headline).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(colors.secondary)
        }
    }

    private var eyebrow: LocalizedStringKey {
        if store.access == .unlockedLifetime { return "已永久解锁" }
        if let waitingTitle { return waitingTitle }
        if store.access == .lockedExpired { return "14 天试用已结束" }
        if unavailable { return "暂时无法载入" }
        if trialUnavailable { return "永久解锁" }
        return "专注阅读，轻松开始"
    }

    private var headline: LocalizedStringKey {
        if store.access == .unlockedLifetime { return "安心阅读，随时继续。" }
        if store.operation == .restoring { return "正在为你恢复。" }
        if store.operation != nil { return "交给 App Store。" }
        if store.message == .pending { return "批准后，即可继续阅读。" }
        if store.access == .lockedExpired { return "继续你的阅读。" }
        if store.access.remainingDays != nil { return "让阅读，继续下去。" }
        if unavailable { return "稍后再试，也没关系。" }
        if trialUnavailable { return "随时开始阅读。" }
        return "先读 14 天，再决定。"
    }

    private var subtitle: LocalizedStringKey {
        if store.access == .unlockedLifetime { return "全部功能已解锁，无需再次购买。" }
        if store.operation == .restoring { return "正在与 App Store 核对购买记录。请完成系统要求的验证。" }
        if store.operation != nil { return "请在系统购买窗口中确认或取消。完成后会自动更新解锁状态。" }
        if store.message == .pending { return "这次购买正在等待批准。收到结果后会自动更新，无需重复购买。" }
        if store.access == .lockedExpired { return "一次购买，永久解锁全部功能。无需订阅，也没有自动续费。" }
        if store.access.remainingDays != nil { return "你的全部功能仍可使用。试用结束前或之后，都可以购买永久解锁。" }
        if unavailable { return "暂时无法获取商品信息。请重试；如果持续出现，可以联系使用支持。" }
        if trialUnavailable { return "试用目前暂不可用。你可以稍后重试，或直接购买永久使用。" }
        if store.isLoadingProducts && store.product == nil { return "我们正在载入你所在地区的购买价格。" }
        return "免费体验全部功能。到期后，一次购买即可永久使用。"
    }

    private func benefit(_ title: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark").foregroundStyle(colors.accent).accessibilityHidden(true)
            Text(title)
        }
    }

    private var price: some View {
        VStack(spacing: 18) {
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    priceDescription
                    Spacer(minLength: 0)
                    priceValue
                }
                VStack(alignment: .leading, spacing: 12) { priceDescription; priceValue }
            }
            .accessibilityElement(children: .combine)
            Divider()
        }
    }

    private var priceDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("永久解锁").font(.headline)
            Text("一次购买 · 无需订阅").font(.caption).foregroundStyle(colors.secondary)
        }
    }

    private var priceValue: some View {
        Group {
            if let product = store.product {
                Text(verbatim: product.displayPrice).font(.title2.bold())
            } else if store.isLoadingProducts {
                ProgressView("正在载入价格…").font(.subheadline)
            } else {
                Text("暂不可用").font(.headline)
            }
        }
        .accessibilityIdentifier("paywall.price")
    }

    @ViewBuilder private var feedback: some View {
        if store.access == .lockedExpired || (store.access != .unlockedLifetime && store.catalogMessage != nil) || store.message != nil || store.operation != nil {
            VStack(alignment: .leading, spacing: 10) {
                if store.access == .lockedExpired {
                    Text("试用到期后暂时无法打开文档。原文件和资料库都已保留，解锁后可继续阅读。")
                }
                if let operation = store.operation {
                    switch operation {
                    case .purchasing: ProgressView("正在与 App Store 通信…")
                    case .restoring: ProgressView("正在恢复购买…")
                    case .verifying: ProgressView("正在验证购买…")
                    }
                }
                if store.access != .unlockedLifetime, let message = store.catalogMessage { PurchaseStatusMessage(message: message) }
                if let message = store.message { PurchaseStatusMessage(message: message) }
            }
            .font(.subheadline)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.selection, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("paywall.feedback")
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if store.access == .unlockedLifetime {
                primary("继续阅读", id: "continue") { dismiss() }
            } else if let waitingTitle {
                primary(waitingTitle, id: "waiting") {}.disabled(true)
            } else if store.product != nil {
                if store.access == .lockedNotStarted && store.trialProduct != nil {
                    primary("开始 14 天免费试用", id: "trial") { Task { await store.purchase(trial: true) } }
                        .disabled(store.isBusy)
                    purchaseButton(primary: false)
                } else {
                    purchaseButton(primary: true)
                }
            } else {
                primary(store.isLoadingProducts ? "正在载入价格…" : "重新载入", id: "retry") { Task { await store.loadProduct() } }
                    .disabled(store.isLoadingProducts)
            }
            if store.access != .unlockedLifetime {
                if store.access.remainingDays != nil {
                    Button("继续阅读") { dismiss() }.frame(minHeight: 44)
                } else if store.access == .lockedExpired {
                    Button("管理资料") {
                        if let onManageSources { onManageSources() } else { dismiss() }
                    }.frame(minHeight: 44).accessibilityIdentifier("paywall.manage")
                }
                if store.product != nil && (needsProducts || store.catalogMessage != nil) {
                    Button("重新载入") { Task { await store.loadProduct() } }
                        .frame(minHeight: 44).disabled(store.isLoadingProducts)
                }
                if store.product == nil {
                    Text("价格载入后才能开始试用或购买。")
                        .font(.footnote).foregroundStyle(colors.secondary)
                }
            }
        }
        .font(.body.weight(.semibold)).foregroundStyle(colors.accent).frame(maxWidth: .infinity)
    }

    private func primary(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(colors.paper).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24).padding(12)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 14))
        .accessibilityIdentifier("paywall.\(id)")
    }

    @ViewBuilder private func purchaseButton(primary isPrimary: Bool) -> some View {
        if let product = store.product {
            let title: LocalizedStringKey = isPrimary ? "永久解锁 · \(product.displayPrice)" : "直接购买 · \(product.displayPrice)"
            if isPrimary {
                primary(title, id: "purchase") { Task { await store.purchase() } }.disabled(store.isBusy)
            } else {
                Button(title) { Task { await store.purchase() } }
                    .frame(minHeight: 44).disabled(store.isBusy).accessibilityIdentifier("paywall.purchase")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { footerLinks }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 2) { footerLinks }
            }
            Text("付款由 Apple 处理").foregroundStyle(colors.secondary)
                .accessibilityIdentifier("paywall.payment")
        }
        .font(.footnote).foregroundStyle(colors.accent).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var footerLinks: some View {
        Button { Task { await store.restore() } } label: {
            Text("恢复购买").frame(minHeight: 44).contentShape(Rectangle())
        }
            .disabled(store.isWaitingForRestore || (store.isBusy && store.operation != .restoring))
            .accessibilityIdentifier("paywall.restore")
        Link(destination: URL(string: "https://wivnelo.github.io/i-md-reader/privacy.html")!) {
            Text("隐私政策").frame(minHeight: 44).contentShape(Rectangle())
        }
        Link(destination: URL(string: "https://wivnelo.github.io/i-md-reader/support.html")!) {
            Text("使用支持").frame(minHeight: 44).contentShape(Rectangle())
        }
    }
}

struct PurchaseStatusMessage: View {
    let message: PurchaseMessage
    var body: some View {
        switch message {
        case .productUnavailable: Text("暂时无法获取商品信息，请稍后重试。")
        case .productLoadFailed: Text("无法连接 App Store，请稍后重试。")
        case .productLoadTimedOut: Text("商品信息加载超时，请重试。")
        case .trialUnavailable: Text("暂时无法开始试用，仍可购买永久解锁。")
        case .pending: Text("购买正在等待批准。")
        case .unverified: Text("无法验证这次购买，请稍后重试。")
        case .purchaseFailed: Text("购买未完成，请稍后重试。")
        case .restored: Text("已恢复购买。")
        case .nothingToRestore: Text("没有可恢复的购买。")
        case .restoreFailed: Text("恢复购买失败，请稍后重试。")
        case .purchaseWaiting: Text("仍在等待 App Store，请完成或取消系统购买窗口。")
        case .restoreWaiting: Text("仍在等待 App Store 恢复购买。你可以重试等待，或稍后重新打开此页面。")
        }
    }
}
#endif
