import XCTest
import UIKit

final class FullAppUITests: XCTestCase {
    private static let launchArguments = ["-IMDDisableCloudKit", "-readingSampleRemoved", "NO", "-readerLanguage", "en", "-AppleLanguages", "(en)"]

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

    @MainActor private func launchReader() -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments
        app.launch()
        guard app.webViews.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 20) else {
            record("reading-missing", app: app)
            XCTFail("The reader must open without any gate"); return nil
        }
        return app
    }

    @MainActor func testNavigationAndRotation() async throws {
        guard let app = launchReader() else { return }
        record("reading-portrait", app: app)
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
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.wait(for: \.frame.size, toEqual: CGSize(width: portraitSize.height, height: portraitSize.width), timeout: 10))
        defer { XCUIDevice.shared.orientation = .portrait }
        // Judge the landscape layout by the UI: a hidden list means a regular-width detail-only split (e.g. Pro Max).
        let listShownAfterRotation = sample.wait(for: \.isHittable, toEqual: true, timeout: 5)
        if !listShownAfterRotation {
            let sidebar = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(["Sidebar", "Show Sidebar", "Toggle Sidebar"].contains(sidebar.label), "Inspect landscape sidebar control: " + sidebar.label)
            sidebar.tap()
        }
        XCTAssertTrue(sample.wait(for: \.isHittable, toEqual: true, timeout: 10))
        // Only a compact stack (portrait compact and list still shown, e.g. SE) hides the article.
        if listShownAfterRotation && portraitSize.width < 600 { XCTAssertFalse(app.webViews.firstMatch.isHittable) }
        record("library-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.wait(for: \.frame.size, toEqual: portraitSize, timeout: 10))
        if !sample.wait(for: \.isHittable, toEqual: true, timeout: 5) {
            // iPad may collapse the sidebar on rotation; that behavior is not being redesigned.
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(sample.wait(for: \.isHittable, toEqual: true, timeout: 10))
        sample.tap()
        XCTAssertTrue(app.webViews.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["为阅读留一点空间"].firstMatch.waitForExistence(timeout: 20))
        record("article-after-rotation", app: app)
    }

    @MainActor func testSettingsAndDocumentLink() async throws {
        guard let app = launchReader() else { return }
        let settings = app.buttons["App settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        for title in ["GitHub access", "iCloud sync", "Offline cache"] {
            settings.tap()
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), title)
            if title == "GitHub access" {
                record("settings-menu", app: app)
                // No purchase, trial or restore entry remains in the settings menu.
                for removed in ["Trial and Purchase", "Restore Purchases", "Unlocked"] {
                    XCTAssertFalse(app.buttons[removed].exists, removed)
                }
                XCTAssertTrue(app.descendants(matching: .any)["Privacy Policy"].firstMatch.exists)
            }
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), title)
            record("settings-" + title, app: app)
            app.buttons["Done"].tap()
        }
        var link = URLComponents(string: "imdreader://open")!
        link.queryItems = [URLQueryItem(name: "key", value: "E4072B41-1284-4D82-82BE-846370D11759|/长文滚动检查.md")]
        // Deliver the link from a foreground system caller to the running app.
        XCUIApplication(bundleIdentifier: try XCTUnwrap(Bundle.main.bundleIdentifier)).activate()
        let opened = await UIApplication.shared.open(try XCTUnwrap(link.url))
        XCTAssertTrue(opened)
        app.activate()
        XCTAssertTrue(app.webViews.staticTexts["长文滚动检查"].firstMatch.waitForExistence(timeout: 20))
        record("link-opened-document", app: app)
    }
}
