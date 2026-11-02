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
