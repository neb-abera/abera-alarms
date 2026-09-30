import XCTest

/// Every screen and button, driven through the app with abera.tech and
/// AlarmKit in memory (`-demo`, App/Demo.swift).
@MainActor
final class AlarmsUITests: XCTestCase {
    static let link = "aberaalarms://pair#token=aat_" + String(repeating: "D", count: 43)

    private func launch(_ arguments: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["alarm-\(key)"]
    }

    // MARK: Pairing

    func testPairingWithAPastedLinkShowsTheAlarms() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(Self.link)
        app.buttons["pair"].tap()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Set on this phone"].firstMatch.exists)
    }

    func testALinkWithABadTokenIsRefused() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("aberaalarms://pair#token=aat_short")
        app.buttons["pair"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pairing-error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "standup").exists)
    }

    func testATokenTheServerRefusesIsRefused() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("aberaalarms://pair#token=aat_" + String(repeating: "X", count: 43))
        app.buttons["pair"].tap()
        let error = app.descendants(matching: .any)["pairing-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("refused"))
    }

    // MARK: The list

    func testTheListShowsAlarmsAndNotNotifications() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        XCTAssertTrue(row(app, "pt").exists)
        XCTAssertFalse(row(app, "lunch").exists)
        XCTAssertFalse(row(app, "dinner").exists)
        XCTAssertTrue(app.staticTexts["1 notification(s) go through Pushover only."].exists)

        app.buttons["All events"].tap()
        XCTAssertTrue(row(app, "lunch").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "dinner").exists)
    }

    // MARK: Type

    func testMakingAnEventAnAlarmSetsItOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["All events"].tap()
        let type = app.buttons["type-dinner"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.tap()
        app.buttons["Ring until stopped"].tap()
        XCTAssertTrue(waitFor(type, labelContaining: "Ring until stopped"))

        app.buttons["Alarms"].tap()
        let dinner = row(app, "dinner")
        XCTAssertTrue(dinner.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(dinner, labelContaining: "Set on this phone"))
    }

    func testMakingAnAlarmNoneTakesItOffThePhone() {
        let app = launch()
        let type = app.buttons["type-standup"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
        app.buttons["Off"].tap()
        XCTAssertTrue(row(app, "pt").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForGone(row(app, "standup")))
    }

    // MARK: New event

    func testANewAlarmEventRingsOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        let title = app.textFields["event-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Dentist")
        app.buttons["add-event"].tap()

        let dentist = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'alarm-created-' AND label CONTAINS 'Dentist'")
        ).firstMatch
        XCTAssertTrue(dentist.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(dentist, labelContaining: "Set on this phone"), dentist.label)
    }

    func testANewAlarmNeedsOnlyATime() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        let add = app.buttons["add-event"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.tap()

        let made = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'alarm-created-' AND label CONTAINS 'Alarm'")
        ).firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(made, labelContaining: "Set on this phone"), made.label)
    }

    func testAdvancedOptionsStartClosed() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        XCTAssertTrue(app.buttons["add-event"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Rings at the start"].exists)
        app.buttons["Advanced"].tap()
        XCTAssertTrue(app.staticTexts["Rings at the start"].waitForExistence(timeout: 5))
    }

    func testAnAlarmAcknowledgedInABrowserSaysSo() {
        let app = launch()
        let brief = row(app, "brief")
        XCTAssertTrue(brief.waitForExistence(timeout: 10))
        XCTAssertTrue(brief.label.contains("Acknowledged in a browser"))
    }

    // MARK: Skip

    func testSkipAndUnskip() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.swipeLeft()
        app.buttons["Skip"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Skipped"))

        standup.swipeLeft()
        app.buttons["Unskip"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Set on this phone"))
    }

    // MARK: Mute

    func testMuteAndUnmute() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["menu"].tap()
        app.buttons["Mute for an hour"].tap()
        let muted = app.descendants(matching: .any)["muted"].firstMatch
        XCTAssertTrue(muted.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(row(app, "standup"), labelContaining: "Muted"))

        app.buttons["Unmute"].firstMatch.tap()
        XCTAssertTrue(waitFor(row(app, "standup"), labelContaining: "Set on this phone"))
        XCTAssertFalse(muted.exists)
    }

    // MARK: Offline

    func testOfflineSaysTheAlarmsStillRing() {
        let app = launch("-demo-offline")
        let error = app.descendants(matching: .any)["sync-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("Offline"))
    }

    // MARK: Unpair

    func testUnpairReturnsToThePairingScreen() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["menu"].tap()
        app.buttons["Unpair this phone"].tap()
        app.buttons["Unpair and remove its alarms"].tap()
        XCTAssertTrue(app.buttons["pair"].waitForExistence(timeout: 5))
    }

    private func waitForGone(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }

    private func waitFor(_ element: XCUIElement, labelContaining text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }
}
