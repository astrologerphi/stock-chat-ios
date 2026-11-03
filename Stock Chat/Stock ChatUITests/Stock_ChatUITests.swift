//
//  Stock_ChatUITests.swift
//  Stock ChatUITests
//
//  Created by Fei HH on 2026/10/30.
//

import XCTest

final class Stock_ChatUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsSearchAndDetail() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        snapshot(app, "1-home")

        tabBar.buttons["ETFs"].tap()
        XCTAssertTrue(app.navigationBars["ETFs"].waitForExistence(timeout: 5))
        snapshot(app, "2-etfs")

        tabBar.buttons["Stocks"].tap()
        XCTAssertTrue(app.navigationBars["Stocks"].waitForExistence(timeout: 5))
        snapshot(app, "3-stocks")

        tabBar.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        snapshot(app, "4-search")

        field.tap()
        field.typeText("NVDA")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "NVIDIA Corporation")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        snapshot(app, "5-results")

        result.tap()
        XCTAssertTrue(app.navigationBars["NVDA"].waitForExistence(timeout: 10))
        sleep(3)
        snapshot(app, "6-detail")
        app.swipeUp()
        app.swipeUp()
        sleep(2)
        snapshot(app, "7-detail-scrolled")
    }

    @MainActor
    func testSettingsAPIKeys() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.navigationBars["Markets"].buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snapshot(app, "8-settings")

        // The built-in key from .secrets should be accepted.
        app.buttons["Test Key"].firstMatch.tap()
        XCTAssertTrue(element(app, containing: "Valid").waitForExistence(timeout: 20))

        // A saved key overrides the built-in one and is rejected by FMP.
        let field = app.secureTextFields["fmp-key-field"]
        field.tap()
        field.typeText("invalid-test-key")
        app.buttons["Save Key"].firstMatch.tap()
        XCTAssertTrue(element(app, containing: "Rejected").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, containing: "Saved in Settings").exists)
        snapshot(app, "9-settings-rejected")

        app.navigationBars["Settings"].buttons["Done"].tap()
        let goToSettings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(element(app, containing: "API key was rejected").waitForExistence(timeout: 20))
        snapshot(app, "10-home-rejected")

        // Removing the saved key falls back to the built-in key.
        goToSettings.tap()
        app.buttons["Remove Saved Key"].firstMatch.tap()
        XCTAssertTrue(element(app, containing: "Built in (.secrets)").waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Markets"].waitForExistence(timeout: 5))
        sleep(5)
        XCTAssertFalse(element(app, containing: "API key was rejected").exists)
    }

    @MainActor
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
