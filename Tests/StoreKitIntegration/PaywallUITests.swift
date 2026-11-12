import XCTest
import StoreKitTest
import StoreKit
import ReaderCore

final class PaywallUITests: XCTestCase {
    @MainActor private var session: SKTestSession?
    @MainActor private func launch(state: String = "new", locale: String = "zh-Hans", theme: String = "light", large: Bool = false) async throws -> XCUIApplication {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        self.session = session
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.askToBuyEnabled = state == "pending"
        let app = XCUIApplication()
        app.launchArguments = ["-paywall-qa", "-state", state, "-locale", locale, "-theme", theme, "-type", large ? "large" : "normal"]
        app.launch()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 20))
        // Establish StoreKit before seeding, then relaunch to read the dated receipt snapshot.
        if state == "owned" { try await session.buyProduct(identifier: PurchaseConfig.lifetimeProductID) }
        if state == "expired" || state == "trial" {
            let days = state == "expired" ? 15 : 11
            try await session.buyProduct(identifier: PurchaseConfig.trialProductID, options: [.purchaseDate(Date().addingTimeInterval(-Double(days) * 86400))])
        }
        if ["owned", "expired", "trial"].contains(state) {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 20))
        }
        if state == "expired" { XCTAssertTrue(app.staticTexts["14 天试用已结束"].waitForExistence(timeout: 20)) }
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let viewport = app.scrollViews["paywall.content"]
        for _ in 0..<12 {
            if element.exists && viewport.frame.contains(element.frame) { return }
            if element.exists && element.frame.minY < viewport.frame.minY { viewport.swipeDown() }
            else { viewport.swipeUp() }
        }
        XCTAssertTrue(element.exists && viewport.frame.contains(element.frame))
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testTrialPurchaseAndClose() async throws {
        let app = try await launch()
        capture("iphone-zh-new")
        let trial = app.buttons["paywall.trial"]
        reveal(trial, in: app)
        XCTAssertTrue(trial.isEnabled)
        trial.tap()
        let continueButton = app.buttons["继续阅读"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 20))
        reveal(continueButton, in: app)
        continueButton.tap()
        XCTAssertTrue(app.buttons["qa.show"].waitForExistence(timeout: 5))
    }

    @MainActor func testExpiredPurchaseAndRestoreWithoutRecords() async throws {
        var app = try await launch(state: "expired")
        capture("iphone-zh-expired")
        let purchase = app.buttons["paywall.purchase"]
        reveal(purchase, in: app)
        purchase.tap()
        XCTAssertTrue(app.buttons["paywall.continue"].waitForExistence(timeout: 20))
        capture("iphone-zh-owned")
        app.terminate()
        app = try await launch()
        let restore = app.buttons["paywall.restore"]
        reveal(restore, in: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["没有可恢复的购买。"].waitForExistence(timeout: 20))
    }

    @MainActor func testFailedAndPartialCatalog() async throws {
        var app = try await launch(state: "failed", theme: "dark")
        capture("iphone-zh-dark-failed")
        XCTAssertFalse(app.buttons["paywall.purchase"].exists)
        XCTAssertFalse(app.buttons["paywall.trial"].exists)
        reveal(app.buttons["paywall.restore"], in: app)
        XCTAssertTrue(app.buttons["paywall.restore"].isEnabled)
        app.terminate()
        app = try await launch(state: "partial")
        reveal(app.buttons["paywall.purchase"], in: app)
        XCTAssertTrue(app.buttons["paywall.purchase"].isEnabled)
        XCTAssertFalse(app.buttons["paywall.trial"].exists)
        capture("iphone-zh-partial")
    }

    @MainActor func testLanguagesAndLargeTextRemainReachable() async throws {
        var normalButtonHeight: CGFloat = 0
        for locale in ["en", "zh-Hant", "ja", "ko"] {
            let app = try await launch(locale: locale, theme: locale == "ko" ? "dark" : "light")
            capture("iphone-\(locale)-new")
            reveal(app.buttons["paywall.trial"], in: app)
            XCTAssertTrue(app.buttons["paywall.trial"].isEnabled)
            if locale == "en" { normalButtonHeight = app.buttons["paywall.trial"].frame.height }
            reveal(app.buttons["paywall.restore"], in: app)
            let terms = app.links["paywall.terms"]
            reveal(terms, in: app)
            XCTAssertTrue(terms.exists)
            XCTAssertGreaterThanOrEqual(terms.frame.height, 44)
            reveal(app.staticTexts["paywall.payment"], in: app)
            capture("iphone-\(locale)-footer")
            app.terminate()
        }
        let app = try await launch(locale: "en", large: true)
        capture("iphone-en-large-top")
        reveal(app.buttons["paywall.trial"], in: app)
        XCTAssertGreaterThan(app.buttons["paywall.trial"].frame.height, normalButtonHeight)
        capture("iphone-en-large-actions")
        reveal(app.buttons["paywall.restore"], in: app)
        let terms = app.links["paywall.terms"]
        reveal(terms, in: app)
        XCTAssertTrue(terms.exists)
        XCTAssertGreaterThanOrEqual(terms.frame.height, 44)
        reveal(app.staticTexts["paywall.payment"], in: app)
        capture("iphone-en-large-footer")
        // The header scrolls with the content; scroll back up to reach the close button.
        reveal(app.buttons["paywall.close"], in: app)
        XCTAssertTrue(app.buttons["paywall.close"].isHittable)
    }

    @MainActor func testLandscapeKeepsActionsReachable() async throws {
        let app = try await launch(locale: "en", theme: "dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        reveal(app.buttons["paywall.trial"], in: app)
        capture("landscape-en-dark-actions")
        reveal(app.buttons["paywall.restore"], in: app)
        reveal(app.buttons["paywall.close"], in: app)
        XCTAssertTrue(app.buttons["paywall.close"].isHittable)
    }

    @MainActor func testPendingApprovalPreventsDuplicatePurchase() async throws {
        let app = try await launch(state: "pending")
        let waiting = app.buttons["paywall.waiting"]
        reveal(waiting, in: app)
        XCTAssertFalse(waiting.isEnabled)
        XCTAssertFalse(app.buttons["paywall.purchase"].exists)
        XCTAssertFalse(app.buttons["paywall.trial"].exists)
        capture("pending-approval")
        let session = try XCTUnwrap(session)
        let transaction = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        XCTAssertTrue(app.buttons["paywall.continue"].waitForExistence(timeout: 20))
    }
}
