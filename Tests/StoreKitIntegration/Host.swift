import SwiftUI
import StoreKit
import ReaderCore

// A separate test host: no ReaderStore, CloudKit, production identifiers or files.
@main
struct StoreKitTestHost: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-paywall-qa") {
                PaywallTestScreen()
            } else { Text("iMDReader StoreKit tests") }
        }
    }
}

@MainActor private final class PreviewStorage: PurchaseAccessStorage {
    var cache: PurchaseAccessCache?
    func read() throws -> PurchaseAccessCache? { cache }
    func write(_ cache: PurchaseAccessCache) throws { self.cache = cache }
}

private func argument(_ key: String, fallback: String) -> String {
    let values = ProcessInfo.processInfo.arguments
    guard let index = values.firstIndex(of: key), index + 1 < values.count else { return fallback }
    return values[index + 1]
}

private struct PaywallTestScreen: View {
    @StateObject private var store: PurchaseStore
    @State private var isPresented = false
    private let state = argument("-state", fallback: "new")

    init() {
        let state = argument("-state", fallback: "new")
        _store = StateObject(wrappedValue: PurchaseStore(config: .init(isEnabled: true), storage: PreviewStorage(), fetchProducts: { ids in
            if state == "failed" { throw URLError(.notConnectedToInternet) }
            return try await Product.products(for: state == "partial" ? [PurchaseConfig.lifetimeProductID] : ids)
        }))
    }

    var body: some View {
        VStack {
            Text("iMDReader StoreKit tests")
            Button("Show paywall") { isPresented = true }.accessibilityIdentifier("qa.show")
        }
        .sheet(isPresented: $isPresented) {
            PurchaseSheet(store: store)
                .dynamicTypeSize(argument("-type", fallback: "normal") == "large" ? .accessibility3 : .large)
        }
        .environment(\.locale, Locale(identifier: argument("-locale", fallback: "zh-Hans")))
        .preferredColorScheme(argument("-theme", fallback: "light") == "dark" ? .dark : .light)
        .task {
            await store.start()
            if state == "pending" { await store.purchase() }
            isPresented = true
        }
    }
}
