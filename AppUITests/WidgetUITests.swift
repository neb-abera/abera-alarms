import XCTest

/// The Home Screen widgets, added and read through Springboard as on the
/// phone: long-press the Home Screen, Edit, Add Widget, search for Alarms,
/// pick the widget. Each test reads the widget with the app open, taps it
/// to open the app, then reads it again with the app closed.
///
/// The Lock Screen widgets are not driven here. XCUITest has no public way
/// to lock the simulator or to open the Lock Screen's Customize editor.
/// They draw the same entries from the same snapshot, which AlarmCore's
/// WidgetSnapshotTests cover.
@MainActor
final class WidgetUITests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Starts the demo, which writes the widgets' snapshot, then goes home.
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        // The Calendar tab is up once the demo's first sync is done, and the
        // snapshot is written at its end.
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(
            poll(15) { app.descendants(matching: .any)["alarm-standup"].exists }, app.debugDescription)
        XCUIDevice.shared.press(.home)
        return app
    }

    private func poll(_ timeout: TimeInterval, _ holds: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !holds() {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return true
    }

    /// The first element on the Home Screen whose label holds `text`.
    private func onHomeScreen(_ text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Long-press, Edit, Add Widget, search, then swipe to the named widget.
    /// The gallery shows the app's widgets one size per page.
    private func addWidget(named name: String) {
        // The bottom of the first page, above the Dock, is empty on a
        // simulator.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 1.5)
        let editHomeScreen = springboard.buttons["Edit Home Screen"].firstMatch
        if editHomeScreen.waitForExistence(timeout: 2) { editHomeScreen.tap() }
        let add = springboard.buttons["Add Widget"].firstMatch
        if !add.waitForExistence(timeout: 3) {
            let edit = springboard.buttons["Edit"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit button:\n\(springboard.debugDescription)")
            edit.tap()
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add Widget:\n\(springboard.debugDescription)")
        add.tap()

        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "no widget search:\n\(springboard.debugDescription)")
        search.tap()
        search.typeText("Alarms")
        // The app's own row in the results, not the Clock app's alarm widget.
        let row = springboard.cells.matching(NSPredicate(format: "label == 'Alarms'")).firstMatch
        let fallback = springboard.buttons.matching(NSPredicate(format: "label == 'Alarms'")).firstMatch
        XCTAssertTrue(
            poll(10) { row.exists || fallback.exists }, "no Alarms in the search:\n\(springboard.debugDescription)")
        (row.exists ? row : fallback).tap()

        let title = springboard.staticTexts[name].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "no \(name) widget:\n\(springboard.debugDescription)")
        for _ in 0..<6 where !title.isHittable {
            springboard.swipeLeft()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        let place = springboard.buttons["Add Widget"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5), "no Add Widget:\n\(springboard.debugDescription)")
        place.tap()
        let done = springboard.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
    }

    /// Takes the widget off the Home Screen, so the next test starts clean.
    private func removeWidget(showing text: String) {
        XCUIDevice.shared.press(.home)
        let widget = onHomeScreen(text)
        guard widget.waitForExistence(timeout: 5) else { return }
        widget.press(forDuration: 1.5)
        let remove = springboard.buttons["Remove Widget"].firstMatch
        guard remove.waitForExistence(timeout: 5) else { return }
        remove.tap()
        let confirm = springboard.alerts.buttons["Remove"].firstMatch
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        let done = springboard.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    /// Reads the widget, taps it to open the app, then closes the app and
    /// reads it again: the widget draws from the snapshot with no app running.
    private func check(_ app: XCUIApplication, shows texts: [String]) {
        for text in texts {
            XCTAssertTrue(
                onHomeScreen(text).waitForExistence(timeout: 20),
                "the widget does not show \(text) with the app open:\n\(springboard.debugDescription)")
        }
        onHomeScreen(texts[0]).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "a tap on the widget did not open the app")
        XCUIDevice.shared.press(.home)
        app.terminate()
        for text in texts {
            XCTAssertTrue(
                onHomeScreen(text).waitForExistence(timeout: 20),
                "the widget does not show \(text) with the app closed:\n\(springboard.debugDescription)")
        }
    }

    /// The demo's next ring: Standup, an hour after launch, unless Wake's
    /// weekday 05:30 comes first.
    private var nextDemoAlarm: String {
        let now = Date()
        let calendar = Calendar.current
        let wake = (0..<8).compactMap { day -> Date? in
            guard let date = calendar.date(byAdding: .day, value: day, to: now),
                let at = calendar.date(bySettingHour: 5, minute: 30, second: 0, of: date),
                at > now, (2...6).contains(calendar.component(.weekday, from: at))
            else { return nil }
            return at
        }.min()!
        return wake < now.addingTimeInterval(3600) ? "Wake" : "Standup"
    }

    func testTheNextAlarmWidgetShowsTheNextRingOnTheHomeScreen() {
        let app = launchDemo()
        let expected = nextDemoAlarm
        addTeardownBlock { @MainActor in self.removeWidget(showing: expected) }
        addWidget(named: "Next alarm")
        check(app, shows: [expected])
    }

    /// With no countdown chosen, the widget shows the next to come: the
    /// demo's Home, 41 days out, in its own zone, Asia/Amman.
    func testTheCountdownWidgetShowsTheNextCountdownOnTheHomeScreen() {
        let app = launchDemo()
        addTeardownBlock { @MainActor in self.removeWidget(showing: "Asia/Amman") }
        addWidget(named: "Countdown")
        check(app, shows: ["41 days", "Home", "Asia/Amman"])
    }
}
