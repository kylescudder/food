import XCTest

/// Drives the installed app on a simulator: a new household is created, the seeded
/// week plan and recipes appear, and a shopping item can be added. `-UITestInMemoryStore` keeps
/// every run on a fresh, local-only store (no iCloud account or CloudKit access).
final class HouseholdJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"]
        app.launch()
    }

    override func tearDown() {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func testNewHouseholdSeesSeededWeekAndRecipesAndCanAddShoppingItem() {
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 20))

        let name = app.textFields["Household name"]
        XCTAssertTrue(name.exists)
        name.tap()
        name.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText(XCUIKeyboardKey.delete.rawValue)
        name.typeText("E2E Kitchen")
        app.buttons["Create Household"].tap()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))
        // A new household starts with this week's seeded meal plan.
        XCTAssertTrue(app.navigationBars["This Week"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Shawarma Tofu Wraps"].waitForExistence(timeout: 10))

        tabs.buttons["Recipes"].tap()
        XCTAssertTrue(app.navigationBars["Recipes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Protein Porridge"].waitForExistence(timeout: 10))

        tabs.buttons["Shopping"].tap()
        XCTAssertTrue(app.staticTexts["No Shopping Items"].waitForExistence(timeout: 10))
        app.buttons["Add Item"].tap()
        let item = app.textFields["Item"]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        item.typeText("Oat milk")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Oat milk"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No Shopping Items"].exists)
    }

    func testJoinHouseholdExplainsHowToAcceptAnInvitation() {
        XCTAssertTrue(app.buttons["Join Household"].waitForExistence(timeout: 20))
        app.buttons["Join Household"].tap()
        let alert = app.alerts["Join a Household"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Create Household"].exists)
    }
}
