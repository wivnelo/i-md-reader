import XCTest
import UIKit
import StoreKitTest

final class FullAppUITests: XCTestCase {
    @MainActor private func record(_ name: String, app: XCUIApplication) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews["paywall.content"]
        for _ in 0..<10 {
            if element.exists && scroll.frame.contains(element.frame) { return }
            scroll.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func clearCachedTestPurchase(app: XCUIApplication) {
        // Clearing StoreKit transactions does not clear the App's persistent Keychain grant.
        // Use the actual restore flow, so the fixture needs no production bypass.
        if !app.scrollViews["paywall.content"].waitForExistence(timeout: 3) {
            if app.buttons["Trial and Purchase"].exists {
                app.buttons["Trial and Purchase"].tap()
            } else {
                app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "App settings")).firstMatch.tap()
                app.buttons["Unlocked"].tap()
            }
        }
        XCTAssertTrue(app.scrollViews["paywall.content"].waitForExistence(timeout: 10))
        let restore = app.buttons["paywall.restore"]
        reveal(restore, app: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["There are no purchases to restore."].waitForExistence(timeout: 20))
    }

    @MainActor func testFullAppPurchaseGateAndNavigation() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        let app = XCUIApplication()
        app.launchArguments = ["-IMDPurchaseEnabled", "-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-readerLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        clearCachedTestPurchase(app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["paywall.settings"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["paywall.close"].exists)
        XCTAssertFalse(app.buttons["Trial and Purchase"].exists)
        XCTAssertTrue(app.staticTexts["iMDReader"].exists)
        record("fullapp-startup", app: app)
        let restore = app.buttons["paywall.restore"]
        reveal(restore, app: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["There are no purchases to restore."].waitForExistence(timeout: 20))
        record("fullapp-paywall", app: app)
        record("fullapp-locked", app: app)
        XCTAssertFalse(app.webViews.firstMatch.isHittable)
        XCTAssertTrue(app.buttons["App settings"].exists)
        app.buttons["App settings"].tap()
        record("fullapp-locked-settings", app: app)
        for title in ["GitHub access", "iCloud sync", "Offline cache", "Manage Sources"] {
            XCTAssertTrue(app.buttons[title].isEnabled)
        }
        app.buttons["Manage Sources"].tap()
        XCTAssertTrue(app.navigationBars["Manage Sources"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Remove Source"].exists)
        record("fullapp-locked-source-manager", app: app)
        app.navigationBars["Manage Sources"].buttons.firstMatch.tap()
        for title in ["GitHub access", "iCloud sync", "Offline cache"] {
            app.buttons["App settings"].tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            record("locked-" + title, app: app)
            app.buttons["Done"].tap()
        }
        var link = URLComponents(string: "imdreader://open")!
        link.queryItems = [URLQueryItem(name: "key", value: "E4072B41-1284-4D82-82BE-846370D11759|/长文滚动检查.md")]
        // Deliver the link from a foreground system caller to the running app.
        XCUIApplication(bundleIdentifier: try XCTUnwrap(Bundle.main.bundleIdentifier)).activate()
        let opened = await UIApplication.shared.open(try XCTUnwrap(link.url))
        XCTAssertTrue(opened)
        app.activate()
        XCTAssertTrue(app.buttons["paywall.settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.isHittable)
        let trial = app.buttons["paywall.trial"]
        reveal(trial, app: app)
        trial.tap()
        XCTAssertTrue(app.webViews.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 20))
        XCTAssertTrue(app.webViews.staticTexts["长文滚动检查"].firstMatch.waitForExistence(timeout: 20))
        record("fullapp-reading", app: app)
    }
    @MainActor private func audit(_ name: String, app: XCUIApplication) throws -> [String] {
        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            findings.append("\(issue.auditType.rawValue): \(issue.compactDescription) — \(issue.element?.label ?? "no element") — frame=\(String(describing: issue.element?.frame)) — \(issue.detailedDescription)")
            // Gather every finding; assert at the end, never silently filter warnings.
            return true
        }
        let attachment = XCTAttachment(string: findings.isEmpty ? "No audit findings" : findings.joined(separator: "\n"))
        attachment.name = name + "-audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        return findings
    }

    @MainActor func testAccessibilityAuditWithoutSpeech() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        let app = XCUIApplication()
        app.launchArguments = ["-IMDPurchaseEnabled", "-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-readerLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        clearCachedTestPurchase(app: app)
        try await session.buyProduct(identifier: "com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.trial14d", options: [.purchaseDate(Date().addingTimeInterval(-15 * 86400))])
        app.terminate()
        app.launch()
        guard app.buttons["paywall.settings"].waitForExistence(timeout: 10) else {
            XCTFail("Expired access must display the new root paywall"); return
        }
        record("fullapp-expired-paywall", app: app)
        let topFindings = try audit("fullapp-expired-paywall-top", app: app)
        reveal(app.buttons["paywall.restore"], app: app)
        XCTAssertGreaterThanOrEqual(app.buttons["paywall.restore"].frame.height, 44)
        let terms = app.buttons["paywall.terms"]
        reveal(terms, app: app)
        XCTAssertTrue(terms.exists)
        XCTAssertGreaterThanOrEqual(terms.frame.height, 44)
        reveal(app.staticTexts["paywall.payment"], app: app)
        record("fullapp-expired-paywall-footer", app: app)
        let footerFindings = try audit("fullapp-expired-paywall-footer", app: app)
        XCTAssertFalse(app.buttons["paywall.close"].exists)
        XCTAssertFalse(app.webViews.firstMatch.isHittable)
        XCTAssertTrue(topFindings.isEmpty && footerFindings.isEmpty,
                      "See attached unfiltered accessibility audit findings")
    }

    @MainActor func testUnlockedNavigationAndRotation() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let app = XCUIApplication()
        app.launchArguments = ["-IMDPurchaseEnabled", "-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-readerLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        try await session.buyProduct(identifier: "com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.lifetime")
        app.terminate()
        app.launch()
        guard app.webViews.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 20) else {
            record("unlocked-reading-missing", app: app)
            XCTFail("Verified lifetime must expose the reader"); return
        }
        record("unlocked-reading-portrait", app: app)
        let back = app.navigationBars.buttons.firstMatch
        let backLabel = back.label
        guard ["Back", "Sidebar", "Show Sidebar", "Toggle Sidebar"].contains(backLabel) else {
            XCTFail("Inspect leading navigation control: " + backLabel); return
        }
        back.tap()
        let sample = app.buttons["为阅读留一点空间.md"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        XCTAssertTrue(sample.isHittable)
        let portraitSize = app.frame.size
        let isPhone = portraitSize.width < 600
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.wait(for: \.frame.size, toEqual: CGSize(width: portraitSize.height, height: portraitSize.width), timeout: 10))
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(sample.wait(for: \.isHittable, toEqual: true, timeout: 10))
        if isPhone { XCTAssertFalse(app.webViews.firstMatch.isHittable) }
        record("unlocked-library-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.wait(for: \.frame.size, toEqual: portraitSize, timeout: 10))
        if isPhone {
            XCTAssertTrue(sample.wait(for: \.isHittable, toEqual: true, timeout: 10))
        } else if !sample.isHittable {
            // iPad may collapse the sidebar on rotation; that behavior is not being redesigned.
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(sample.wait(for: \.isHittable, toEqual: true, timeout: 10))
        sample.tap()
        XCTAssertTrue(app.webViews.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["为阅读留一点空间"].firstMatch.waitForExistence(timeout: 20))
        record("unlocked-article-after-rotation", app: app)
    }

    @MainActor private func tapMenuOption(_ label: String, app: XCUIApplication) {
        let option = app.buttons[label]
        let menu = app.collectionViews.firstMatch
        for _ in 0..<12 {
            if option.exists && option.isHittable { option.tap(); return }
            // Collection frames extend beyond the clipped native menu; drag in its top 200 points.
            let origin = menu.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: menu.frame.width / 2, dy: 200))
                .press(forDuration: 0.01, thenDragTo: origin.withOffset(CGVector(dx: menu.frame.width / 2, dy: 50)))
        }
        XCTFail("Menu option is not reachable: \(label)")
    }

    @MainActor func testExpiredRootPaywallSettingsAndLanguage() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "iMDReader", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        let app = XCUIApplication()
        app.launchArguments = ["-IMDPurchaseEnabled", "-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-readerLanguage", "en", "-AppleLanguages", "(en)"]
        app.launch()
        clearCachedTestPurchase(app: app)
        try await session.buyProduct(identifier: "com.readerprototype.3z4gd8c2jp.ipadmarkdownreader.trial14d", options: [.purchaseDate(Date().addingTimeInterval(-15 * 86400))])
        app.terminate()
        for theme in ["light", "dark"] {
            let size = theme == "dark" ? UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue : UIContentSizeCategory.large.rawValue
            app.launchArguments = ["-IMDPurchaseEnabled", "-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-AppleLanguages", "(en)", "-readerTheme", theme, "-UIPreferredContentSizeCategoryName", size]
            app.launch()
            XCTAssertTrue(app.buttons["paywall.settings"].waitForExistence(timeout: 15))
            // Do not pin readerLanguage in launch arguments: it masks UI preference changes.
            app.buttons["paywall.settings"].tap()
            tapMenuOption("English", app: app)
            XCTAssertFalse(app.buttons["paywall.close"].exists)
            XCTAssertFalse(app.buttons["Trial and Purchase"].exists)
            XCTAssertFalse(app.webViews.firstMatch.isHittable)
            XCTAssertTrue(app.staticTexts["iMDReader"].exists)
            record("new-root-expired-" + theme + "-top", app: app)
            let manage = app.buttons["paywall.manage"]
            reveal(manage, app: app)
            manage.tap()
            XCTAssertTrue(app.navigationBars["Manage Sources"].waitForExistence(timeout: 10))
            app.navigationBars["Manage Sources"].buttons.firstMatch.tap()
            reveal(app.buttons["paywall.restore"], app: app)
            let terms = app.buttons["paywall.terms"]
            reveal(terms, app: app)
            XCTAssertTrue(terms.exists)
            XCTAssertGreaterThanOrEqual(terms.frame.height, 44)
            reveal(app.staticTexts["paywall.payment"], app: app)
            record("new-root-expired-" + theme + "-footer", app: app)
            app.buttons["paywall.settings"].tap()
            record("new-root-settings-" + theme, app: app)
            if theme == "light" {
                for language in ["简体中文", "繁體中文", "English", "日本語", "한국어"] {
                    XCTAssertTrue(app.buttons[language].exists)
                }
            }
            tapMenuOption("简体中文", app: app)
            XCTAssertTrue(app.buttons["paywall.settings"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["paywall.settings"].label, "应用设置")
            app.buttons["paywall.settings"].tap()
            tapMenuOption("English", app: app)
            XCTAssertEqual(app.buttons["paywall.settings"].label, "App settings")
            app.terminate()
        }
    }

}
