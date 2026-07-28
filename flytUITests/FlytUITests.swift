//
//  FlytUITests.swift
//  flytUITests
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import XCTest

final class FlytUITests: XCTestCase {

    override func setUpWithError() throws {
        // Later UI steps rarely make sense after one fails, so stop immediately.
        continueAfterFailure = false
    }

    /// Placeholder from the Xcode template; just launches the app.
    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    /// Measures cold-launch time of the app.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
