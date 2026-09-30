import XCTest

/// Every screen and button, driven through the app with abera.tech and
/// AlarmKit in memory (`-demo`, App/Demo.swift).
@MainActor
final class AlarmsUITests: XCTestCase {
    static let link = "aberaalarms://pair#token=aat_" + String(repeating: "D", count: 43)

    /// Starts the app in -demo mode. A paired start opens the Calendar tab
    /// unless `tab` names another one, or nil to stay on Alarms.
    private func launch(_ arguments: String..., tab: String? = "Calendar") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments
        app.launch()
        if let tab, !arguments.contains("-demo-unpaired") { open(tab, in: app) }
        return app
    }

    private func open(_ tab: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
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
        open("Calendar", in: app)
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
        XCTAssertTrue(row(app, "pt|1").exists)
        XCTAssertFalse(row(app, "lunch").exists)
        XCTAssertFalse(row(app, "dinner").exists)
        XCTAssertTrue(app.staticTexts["1 notification(s) go through Pushover only."].exists)

        app.segmentedControls.buttons["All events"].tap()
        XCTAssertTrue(row(app, "lunch").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "dinner").exists)
    }

    // MARK: Type

    func testMakingAnEventAnAlarmSetsItOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.segmentedControls.buttons["All events"].tap()
        let type = app.buttons["type-dinner"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.tap()
        app.buttons["Ring until stopped"].tap()
        XCTAssertTrue(waitFor(type, labelContaining: "Ring until stopped"))

        app.segmentedControls.buttons["Alarms"].tap()
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
        XCTAssertTrue(row(app, "pt|1").waitForExistence(timeout: 5))
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

        // The banner's button. The closed menu holds another "Unmute".
        app.buttons["unmute"].tap()
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

    // MARK: Edit and delete events

    func testEditingAnEventTitle() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let title = app.textFields["edit-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Stand-up")
        app.buttons["save-event"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Stand-up"))
    }

    func testDeletingFromTheEditor() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let delete = app.buttons["delete-event"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete Event"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete All Events"].exists)
        confirm.tap()
        XCTAssertTrue(waitForGone(standup))
    }

    func testDeletingARepeatingEventAsksWhich() {
        let app = launch()
        let pt = row(app, "pt|1")
        XCTAssertTrue(pt.waitForExistence(timeout: 10))
        pt.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let one = app.buttons["Delete This Event"]
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete All Events"].waitForExistence(timeout: 5), app.debugDescription)
        one.tap()
        XCTAssertTrue(waitForGone(pt))
        XCTAssertTrue(row(app, "standup").exists)
    }

    // MARK: Routine alarms

    private func routine(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)["routine-\(label)"].firstMatch
    }

    func testTheAlarmsTabListsRoutinesWithTheirDays() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        XCTAssertTrue(wake.label.contains("Wake, Weekdays"), wake.label)
        XCTAssertTrue(routine(app, "Weekend").label.contains("Weekends"))
    }

    func testAddingARoutineWithDays() {
        let app = launch(tab: nil)
        XCTAssertTrue(routine(app, "Wake").waitForExistence(timeout: 10))
        app.buttons["add-routine"].tap()
        let save = app.buttons["save-routine"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["day-2"].tap()
        app.buttons["day-4"].tap()
        save.tap()
        let added = routine(app, "Alarm")
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        XCTAssertTrue(added.label.contains("Tue Thu"), added.label)
    }

    func testSwitchingARoutineOffAndOn() {
        let app = launch(tab: nil)
        let toggle = app.switches["routine-switch-Wake"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "0"))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "1"))
    }

    func testEditingThenDeletingARoutine() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        wake.tap()
        let label = app.textFields["routine-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        label.typeText("Gym")
        app.buttons["save-routine"].tap()
        let gym = routine(app, "Gym")
        XCTAssertTrue(gym.waitForExistence(timeout: 10), app.debugDescription)

        gym.tap()
        let delete = app.buttons["delete-routine"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(waitForGone(routine(app, "Gym")))
    }

    private func waitFor(_ element: XCUIElement, value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }
}
