import AlarmCore
import AlarmKit
import SwiftUI
import UIKit

/// The app's tabs. The clocks on a tab tick only while it is the one selected.
enum AppTab: Hashable {
    case alarms, timer, calendar, countdowns, dates
}

struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var timer: WorkoutModel
    @State private var tab = AppTab.alarms

    var body: some View {
        Group {
            if !model.started {
                ProgressView()
            } else if model.paired {
                TabView(selection: $tab) {
                    Tab("Alarms", systemImage: "alarm", value: AppTab.alarms) {
                        RoutinesView(model: model, onScreen: tab == .alarms)
                    }
                    Tab("Timer", systemImage: "stopwatch", value: AppTab.timer) {
                        WorkoutView(timer: timer, onScreen: tab == .timer)
                    }
                    Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                        AlarmsView(model: model, onScreen: tab == .calendar)
                    }
                    Tab("Countdowns", systemImage: "hourglass", value: AppTab.countdowns) {
                        CountdownsView(model: model, onScreen: tab == .countdowns)
                    }
                    Tab("Dates", systemImage: "calendar.badge.clock", value: AppTab.dates) {
                        DateCalculatorView()
                    }
                }
            } else {
                PairView(model: model)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { model.blocked }, set: { _ in })) {
            ReadyView(model: model)
        }
        .task { await model.start() }
    }
}

// MARK: Pairing

struct PairView: View {
    @Bindable var model: AppModel
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "On abera.tech/alerts, press Pair a phone. Open the link it shows on this phone, or paste it here."
                    )
                    Link("Open abera.tech/alerts", destination: URL(string: "https://abera.tech/alerts")!)
                }
                Section("Pairing link") {
                    TextField("aberaalarms://pair#token=…", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .accessibilityIdentifier("pairing-link")
                    Button("Pair") { Task { await model.pair(link: link) } }
                        .disabled(link.isEmpty || model.busy)
                        .accessibilityIdentifier("pair")
                }
                if let error = model.pairingError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("pairing-error")
                    }
                }
            }
            .navigationTitle("Pair with abera.tech")
            .overlay { if model.busy { ProgressView() } }
        }
    }
}

// MARK: Alarms

struct AlarmsView: View {
    @Bindable var model: AppModel
    @State private var confirmingUnpair = false
    @State private var addingEvent = false
    var onScreen = true

    var body: some View {
        NavigationStack {
            List {
                ReadinessSection(model: model)
                StatusSection(model: model)
                Section {
                    Picker("Show", selection: $model.showAll) {
                        Text("All events").tag(true)
                        Text("Alarms").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("show")
                }
                if model.days.isEmpty {
                    Section {
                        Text(model.emptyMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("no-alarms")
                    }
                }
                ForEach(model.days, id: \.day) { group in
                    Section(DayHeading.text(for: group.day)) {
                        ForEach(group.alerts) { alert in
                            EventRow(model: model, alert: alert, ticking: onScreen)
                        }
                    }
                }
                Section {
                } footer: {
                    Footer(model: model)
                }
            }
            .navigationTitle("Calendar")
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingEvent = true
                    } label: {
                        Label("New calendar event", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("new-event")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if model.state?.mutedUntil != nil {
                            Button("Unmute") { Task { await model.unmute() } }
                        }
                        Button("Mute for an hour") { Task { await model.mute(.hour) } }
                        Button("Mute until morning") { Task { await model.mute(.morning) } }
                        Link("Settings on abera.tech", destination: URL(string: "https://abera.tech/alerts")!)
                        Button("Unpair this phone", role: .destructive) { confirmingUnpair = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("menu")
                }
            }
            .sheet(isPresented: $addingEvent) {
                NewEventView(model: model)
            }
            .confirmationDialog("Unpair this phone?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
                Button("Unpair and remove its alarms", role: .destructive) { Task { await model.unpair() } }
            } message: {
                Text("The phone stops ringing. Revoke its token on abera.tech/alerts too.")
            }
        }
    }
}

/// "Today", "Tomorrow", then the weekday and date.
enum DayHeading {
    static func text(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct EventRow: View {
    @Bindable var model: AppModel
    let alert: PlannedAlert
    var ticking = true
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.headline)
                Text(
                    "Starts \(alert.startsAt, format: .dateTime.hour().minute()), alert \(alert.alertAt, format: .dateTime.hour().minute())"
                )
                .font(.subheadline)
                if let location = alert.location, !location.isEmpty {
                    Text(location).font(.subheadline).foregroundStyle(.secondary)
                }
                if alert.isAlarm {
                    Text(status).font(.caption).foregroundStyle(statusColor)
                    let held = model.isHeld(alert)
                    if held {
                        TimelineView(Ticking.schedule(ticking)) { context in
                            if let clock = RingClock.text(for: alert, held: held, at: context.date) {
                                Text(clock).font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alarm-\(alert.key)")
            .accessibilityHint("Opens the event to edit or delete it")
            .contentShape(Rectangle())
            .onTapGesture { editing = true }
            Spacer()
            TypeMenu(model: model, alert: alert)
        }
        .sheet(isPresented: $editing) {
            EventEditor(model: model, alert: alert)
        }
        .confirmationDialog(
            "Delete \(alert.title)?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            DeleteChoices(model: model, alert: alert)
        } message: {
            Text("It is removed from Google Calendar, which keeps it in its trash for 30 days.")
        }
        .swipeActions {
            // Red, without the destructive role: that role makes the list
            // start removing the row, and the dialog below goes with it.
            Button("Delete") { confirmingDelete = true }
                .tint(.red)
            if alert.skipped {
                Button("Unskip") { Task { await model.unskip(alert) } }
                    .tint(.blue)
            } else {
                Button("Skip") { Task { await model.skip(alert) } }
                    .tint(.orange)
            }
        }
    }

    private var status: String {
        if alert.acknowledged {
            return Acknowledgement.text(via: alert.acknowledgedVia)
        }
        if alert.skipped { return "Skipped" }
        if alert.muted { return "Muted" }
        return model.isHeld(alert) ? "Set on this phone" : "Not set on this phone"
    }

    private var statusColor: Color {
        if alert.acknowledged || alert.skipped || alert.muted { return .secondary }
        return model.isHeld(alert) ? .green : .red
    }
}

/// Alarm, Notification or None for every occurrence of the event, as the
/// buttons on abera.tech/alerts. An alarm is written to Google Calendar as
/// #critical.
struct TypeMenu: View {
    @Bindable var model: AppModel
    let alert: PlannedAlert

    var body: some View {
        Menu {
            Button {
                Task { await model.setType(alert, AlertType.alarm) }
            } label: {
                Label(TypeMenu.name(AlertType.alarm), systemImage: "alarm")
            }
            Button {
                Task { await model.setType(alert, AlertType.notification) }
            } label: {
                Label(TypeMenu.name(AlertType.notification), systemImage: "bell")
            }
            Button {
                Task { await model.setType(alert, AlertType.none) }
            } label: {
                Label(TypeMenu.name(AlertType.none), systemImage: "bell.slash")
            }
            if alert.typeFrom == "set" {
                Button("Follow the calendar and the default") {
                    Task { await model.setType(alert, AlertType.default) }
                }
            }
        } label: {
            Label(TypeMenu.name(alert.type), systemImage: TypeMenu.symbol(alert.type))
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(alert.isAlarm ? Color.accentColor : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Type of \(alert.title): \(TypeMenu.name(alert.type))")
        .accessibilityIdentifier("type-\(alert.key)")
    }

    static func name(_ type: String) -> String {
        switch type {
        case AlertType.alarm: "Ring until stopped"
        case AlertType.notification: "Ring once"
        default: "Off"
        }
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case AlertType.alarm: "alarm.fill"
        case AlertType.notification: "bell"
        default: "bell.slash"
        }
    }
}

/// Delete this event, or every event in its series when it repeats.
struct DeleteChoices: View {
    @Bindable var model: AppModel
    let alert: PlannedAlert
    var done: () -> Void = {}

    var body: some View {
        if alert.recurring {
            Button("Delete This Event", role: .destructive) { delete(.occurrence) }
            Button("Delete All Events", role: .destructive) { delete(.series) }
        } else {
            Button("Delete Event", role: .destructive) { delete(.occurrence) }
        }
    }

    private func delete(_ scope: EditScope) {
        Task {
            if await model.deleteEvent(alert, scope: scope) { done() }
        }
    }
}

/// A length typed as a number with its unit beside it: "30" and "minutes".
struct SpanField: View {
    let title: String
    @Binding var span: TimeSpan
    let id: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                // Zero shows as an empty field with a grey 0, so a typed
                // number replaces it rather than landing beside it.
                TextField(
                    title,
                    text: Binding(
                        get: { span.amount == 0 ? "" : String(span.amount) },
                        set: { span.amount = TimeSpan.amount(typed: $0) }),
                    prompt: Text("0")
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityIdentifier("\(id)-amount")
                Picker(title, selection: $span.unit) {
                    ForEach(TimeSpan.Unit.allCases, id: \.self) { unit in
                        Text(unit.name(span.amount)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("\(id)-unit")
            }
        }
    }
}

/// The alert on an event: on by default, ringing until stopped, at the
/// start unless a time before it is typed.
struct AlertFields: View {
    @Binding var on: Bool
    @Binding var type: String
    @Binding var lead: TimeSpan
    var series = false

    var body: some View {
        Section {
            Toggle("Alert", isOn: $on)
                .accessibilityIdentifier("event-alert")
            if on {
                Picker("Rings", selection: $type) {
                    Text("Until stopped").tag(AlertType.alarm)
                    Text("Once").tag(AlertType.notification)
                }
                .accessibilityIdentifier("event-type")
                SpanField(title: "Before the start", span: $lead, id: "event-lead")
            }
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let when =
            lead.amount == 0
            ? "at the start" : "\(lead.amount) \(lead.unit.name(lead.amount)) before the start"
        let what =
            !on
            ? "No alert. The event is on Google Calendar."
            : type == AlertType.alarm
                ? "Rings \(when) until you stop it, on the phone and through Pushover."
                : "Rings once, \(when)."
        return series ? what + " The alert covers every event in the series." : what
    }
}

/// Change an event's title, start, length, location and alert, or delete
/// it. abera.tech makes the change in Google Calendar.
struct EventEditor: View {
    @Bindable var model: AppModel
    let alert: PlannedAlert
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var startsAt: Date
    @State private var length: TimeSpan
    @State private var location: String
    @State private var alerts: Bool
    @State private var type: String
    @State private var lead: TimeSpan
    @State private var scope = EditScope.occurrence
    @State private var confirmingDelete = false

    init(model: AppModel, alert: PlannedAlert) {
        self.model = model
        self.alert = alert
        _title = State(initialValue: alert.title)
        _startsAt = State(initialValue: alert.startsAt)
        _length = State(initialValue: TimeSpan(minutes: alert.durationMinutes ?? NewEvent.defaultLength.minutes))
        _location = State(initialValue: alert.location ?? "")
        _alerts = State(initialValue: alert.type != AlertType.none)
        _type = State(initialValue: alert.type == AlertType.notification ? AlertType.notification : AlertType.alarm)
        _lead = State(initialValue: TimeSpan(minutes: alert.leadMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("edit-title")
                    DatePicker("Starts", selection: $startsAt, in: Date()...)
                    if alert.durationMinutes != nil {
                        SpanField(title: "Length", span: $length, id: "edit-length")
                    }
                    TextField("Location", text: $location)
                }
                AlertFields(on: $alerts, type: $type, lead: $lead, series: alert.recurring)
                if alert.recurring {
                    Section {
                        Picker("Change", selection: $scope) {
                            Text("This event").tag(EditScope.occurrence)
                            Text("All events").tag(EditScope.series)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("edit-scope")
                    } footer: {
                        Text("This event repeats.")
                    }
                }
                ForEach(problems, id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let error = model.eventError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("edit-error")
                    }
                }
                Section {
                    Button("Delete Event", role: .destructive) { confirmingDelete = true }
                        .accessibilityIdentifier("delete-event")
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.updateEvent(edit, type: newType) { dismiss() }
                        }
                    }
                    .disabled(!problems.isEmpty || model.busy)
                    .accessibilityIdentifier("save-event")
                }
            }
            .confirmationDialog(
                "Delete \(alert.title)?", isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                DeleteChoices(model: model, alert: alert) { dismiss() }
            } message: {
                Text("It is removed from Google Calendar, which keeps it in its trash for 30 days.")
            }
            .onAppear { model.clearEventError() }
        }
    }

    /// The alert type to set, or nil when it has not changed.
    private var newType: String? {
        let chosen = alerts ? type : AlertType.none
        return chosen == alert.type ? nil : chosen
    }

    private var edit: EventEdit {
        EventEdit(
            key: alert.key, scope: alert.recurring ? scope : .occurrence,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: startsAt,
            durationMinutes: alert.durationMinutes == nil ? nil : length.minutes,
            location: location.isEmpty ? nil : location, leadMinutes: alerts ? lead.minutes : nil)
    }

    private var problems: [String] {
        edit.problems(now: Date())
    }
}

// MARK: New event

/// A new calendar event: when it starts, how long it lasts, and its alert,
/// which is on and rings until stopped unless switched.
struct NewEventView: View {
    /// The title when the field is left empty.
    static let defaultTitle = "Event"

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = NewEvent.defaultStart()
    @State private var length = NewEvent.defaultLength
    @State private var location = ""
    @State private var alerts = true
    @State private var type = AlertType.alarm
    @State private var lead = TimeSpan(0, .minutes)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title, prompt: Text(Self.defaultTitle))
                        .accessibilityIdentifier("event-title")
                    DatePicker("Starts", selection: $startsAt, in: Date()...)
                        .accessibilityIdentifier("event-start")
                    SpanField(title: "Length", span: $length, id: "event-length")
                    TextField("Location", text: $location)
                } footer: {
                    Text("abera.tech adds it to your Google Calendar.")
                }
                AlertFields(on: $alerts, type: $type, lead: $lead)
                ForEach(problems, id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let error = model.eventError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("event-error")
                    }
                }
            }
            .navigationTitle("New Calendar Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if await model.createEvent(event) { dismiss() }
                        }
                    }
                    .disabled(!problems.isEmpty || model.busy)
                    .accessibilityIdentifier("add-event")
                }
            }
            .onAppear { model.clearEventError() }
        }
    }

    private var event: NewEvent {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewEvent(
            title: trimmed.isEmpty ? Self.defaultTitle : trimmed, startsAt: startsAt,
            durationMinutes: length.minutes,
            location: location.isEmpty ? nil : location, type: alerts ? type : AlertType.none,
            leadMinutes: alerts ? lead.minutes : nil)
    }

    private var problems: [String] {
        event.problems(now: Date())
    }
}

struct StatusSection: View {
    @Bindable var model: AppModel

    var body: some View {
        if let until = model.state?.mutedUntil, until > Date() {
            Section {
                HStack {
                    Label(
                        "Muted until \(until, format: .dateTime.weekday().hour().minute())", systemImage: "bell.slash"
                    )
                    .accessibilityIdentifier("muted")
                    Spacer()
                    Button("Unmute") { Task { await model.unmute() } }
                        .accessibilityIdentifier("unmute")
                }
            }
        }
        if let error = model.report?.error {
            Section {
                Label(message(for: error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(error == .offline ? Color.primary : Color.red)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sync-error")
            }
        }
        if let refused = model.report?.refused, !refused.isEmpty {
            Section {
                Label(
                    "\(refused.count) alarm(s) could not be set on this phone.", systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
            }
        }
        if let write = model.state?.calendarWrite {
            Section {
                Label(
                    "Saved on abera.tech, not in Google Calendar: \(write)",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("calendar-write")
            }
        }
        if let fetchError = model.state?.lastFetchError {
            Section {
                Label(
                    "abera.tech could not read the calendar: \(fetchError)",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .foregroundStyle(.red)
            }
        }
    }

    private func message(for error: APIError) -> String {
        switch error {
        case .offline:
            "Offline. The alarms marked Set on this phone ring without a connection."
        case .unpaired:
            "abera.tech refused this phone's token. The alarms already set still ring. Pair again to get new ones."
        default:
            AppModel.describe(error)
        }
    }
}

struct Footer: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let at = model.report?.at, model.report?.error == nil {
                Text("Synced \(at, format: .dateTime.hour().minute()).")
                    .accessibilityIdentifier("synced")
            }
            if model.notificationCount > 0 {
                Text("\(model.notificationCount) notification(s) go through Pushover only.")
            }
            Text(
                "Tap the icon beside an event to choose Ring until stopped, Ring once or Off. Swipe to skip one day. Pull down to sync."
            )
        }
    }
}

// MARK: Ready to ring

/// What iOS tells the app about this phone, for the readiness checks.
struct DeviceReading: Equatable, Sendable {
    var backgroundRefresh: Bool
    var pushRegistered: Bool
    var lowPower: Bool
    /// Nil when iOS does not say.
    var pushover: Bool?
}

/// The phone settings an alarm depends on, and the test alarm.
protocol DeviceChecks: Sendable {
    @MainActor func read() -> DeviceReading
    /// When the owner said the test alarm rang loud enough.
    var testHeardAt: Date? { get }
    func markTestHeard(_ at: Date)
    /// Sets an alarm 10 seconds from now with the chosen sound. False when iOS refused it.
    func ringTest(sound: String) async -> Bool
    /// Starts the timer: a countdown on the Lock Screen that rings until
    /// stopped. Nil when iOS refused it, else when it rings.
    func startTimer(seconds: Int, label: String, sound: String) async -> Date?
    func cancelTimer() async
    /// When the running timer rings. Nil when none runs.
    func timerEndsAt() async -> Date?
}

/// The real phone.
struct SystemDevice: DeviceChecks {
    static let heardKey = "test-alarm-heard-at"
    nonisolated static let testAlarmID = UUID(uuidString: "5E57A1A2-7E57-4000-8000-000000000002")!
    nonisolated static let timerID = UUID(uuidString: "5E57A1A2-7E57-4000-8000-000000000003")!
    static let timerKey = "timer-ends-at"

    func startTimer(seconds: Int, label: String, sound: String) async -> Date? {
        try? AlarmManager.shared.cancel(id: Self.timerID)
        let alert = AlarmPresentation.Alert(title: "\(label)", secondaryButton: nil, secondaryButtonBehavior: nil)
        let countdown = AlarmPresentation.Countdown(title: "\(label)", pauseButton: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: nil),
            metadata: AlarmInfo(key: "timer"),
            tintColor: .accentColor)
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>(
            countdownDuration: .init(preAlert: TimeInterval(seconds), postAlert: nil),
            schedule: nil,
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: AlarmKitScheduler.sound(sound))
        do {
            _ = try await AlarmManager.shared.schedule(id: Self.timerID, configuration: configuration)
            let endsAt = Date().addingTimeInterval(TimeInterval(seconds))
            UserDefaults.standard.set(endsAt, forKey: Self.timerKey)
            return endsAt
        } catch {
            return nil
        }
    }

    func cancelTimer() async {
        try? AlarmManager.shared.cancel(id: Self.timerID)
        UserDefaults.standard.removeObject(forKey: Self.timerKey)
    }

    func timerEndsAt() async -> Date? {
        let running = (try? AlarmManager.shared.alarms.contains { $0.id == Self.timerID }) ?? false
        guard running else {
            UserDefaults.standard.removeObject(forKey: Self.timerKey)
            return nil
        }
        return UserDefaults.standard.object(forKey: Self.timerKey) as? Date
    }

    @MainActor func read() -> DeviceReading {
        let app = UIApplication.shared
        return DeviceReading(
            backgroundRefresh: app.backgroundRefreshStatus == .available,
            pushRegistered: app.isRegisteredForRemoteNotifications,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            // Info.plist lists the pushover scheme, so iOS answers.
            pushover: URL(string: "pushover://").map(app.canOpenURL))
    }

    var testHeardAt: Date? { UserDefaults.standard.object(forKey: Self.heardKey) as? Date }

    func markTestHeard(_ at: Date) { UserDefaults.standard.set(at, forKey: Self.heardKey) }

    func ringTest(sound: String) async -> Bool {
        try? AlarmManager.shared.cancel(id: Self.testAlarmID)
        let alert = AlarmPresentation.Alert(title: "Test alarm", secondaryButton: nil, secondaryButtonBehavior: nil)
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: AlarmInfo(key: "test"),
            tintColor: .accentColor)
        let configuration = AlarmManager.AlarmConfiguration<AlarmInfo>(
            countdownDuration: nil,
            schedule: .fixed(Date().addingTimeInterval(10)),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: AlarmKitScheduler.sound(sound))
        do {
            _ = try await AlarmManager.shared.schedule(id: Self.testAlarmID, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}

/// The checks that fail. The tabs show the warnings at the top. The
/// blocking ones hold the app on the setup screen.
struct ReadinessSection: View {
    @Bindable var model: AppModel
    /// The tabs show the warnings. The setup screen, over them, shows every check.
    var warningsOnly = true

    var body: some View {
        ForEach(model.checks.filter { !warningsOnly || $0.severity == .warning }) { check in
            Section {
                CheckRow(model: model, check: check)
            }
        }
    }
}

/// Every check that fails, until the blocking ones pass. The app opens on
/// it after pairing and on every launch while one fails.
struct ReadyView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Alarms ring only when each item marked red is fixed. The app checks again every time it opens."
                    )
                }
                ReadinessSection(model: model, warningsOnly: false)
            }
            .navigationTitle("Ready to Ring")
            .refreshable { await model.checkReadiness() }
        }
        .interactiveDismissDisabled()
    }
}

struct CheckRow: View {
    @Bindable var model: AppModel
    let check: ReadinessCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                check.title,
                systemImage: check.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle"
            )
            .font(.headline)
            .foregroundStyle(check.severity == .blocking ? Color.red : Color.orange)
            Text(check.detail).font(.subheadline)
            fix
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check-\(check.kind.rawValue)")
    }

    @ViewBuilder private var fix: some View {
        switch check.fix {
        case .allowAlarms where model.permission == .notAsked:
            Button("Allow alarms") { Task { await model.requestPermission() } }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("allow-alarms")
        case .allowAlarms, .openSettings:
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                .accessibilityIdentifier("open-settings-\(check.kind.rawValue)")
        case .testAlarm:
            TestAlarmControls(model: model)
        case .sync:
            Button("Sync now") { Task { await model.sync() } }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("sync-now")
        case .none:
            EmptyView()
        }
    }
}

/// The test alarm: ring it, then say whether it was heard. A silent test
/// shows the settings that set an alarm's volume, and rings again.
struct TestAlarmControls: View {
    @Bindable var model: AppModel

    var body: some View {
        if let at = model.testRingsAt {
            Text(
                "It rings at \(at, format: .dateTime.hour().minute().second()). Lock the phone to hear it as you would at night."
            )
            .font(.subheadline)
            .accessibilityIdentifier("test-rings-at")
            HStack {
                Button("I heard it") { Task { await model.heardTest() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("heard-test")
                Button("I didn't hear it") { model.missedTest() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("missed-test")
            }
        } else if model.testMissed {
            Text(
                "Settings > Sounds & Haptics > Alarms and Timers: turn Match Ringtone Volume off and drag the slider all the way right. Then ring it again. If it is still silent, restart the phone and try once more."
            )
            .font(.subheadline)
            .accessibilityIdentifier("test-missed-help")
            HStack {
                Button("Ring it again") { Task { await model.ringTestAlarm() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ring-test-again")
                Button("Dismiss") { model.dismissTestHelp() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dismiss-test-help")
            }
        } else {
            Button("Ring a test alarm") { Task { await model.ringTestAlarm() } }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ring-test")
        }
        if let error = model.testError {
            Text(error).foregroundStyle(.red).font(.subheadline)
        }
    }
}

// MARK: Timer

/// A timer: a length typed with its unit and an optional label. It counts
/// down on the Lock Screen and in the Dynamic Island, then rings until stopped.
struct TimerSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var length = TimerLength.standard
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Length") {
                        HStack {
                            TextField(
                                "Length",
                                text: Binding(
                                    get: { length.amount == 0 ? "" : String(length.amount) },
                                    set: { length.amount = TimeSpan.amount(typed: $0) }),
                                prompt: Text("0")
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .accessibilityIdentifier("timer-amount")
                            Picker("Unit", selection: $length.unit) {
                                ForEach(TimerLength.Unit.allCases, id: \.self) { unit in
                                    Text(unit.name(length.amount)).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("timer-unit")
                        }
                    }
                    TextField("Label (optional)", text: $label, prompt: Text("Timer"))
                        .accessibilityIdentifier("timer-label")
                } footer: {
                    Text("Counts down on the Lock Screen and rings until you stop it, through silent mode and Focus.")
                }
                ForEach(length.problems, id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let error = model.timerError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task {
                            if await model.startTimer(length, label: label) { dismiss() }
                        }
                    }
                    .disabled(!length.problems.isEmpty)
                    .accessibilityIdentifier("start-timer")
                }
            }
        }
    }
}

/// The running timer at the top of the Alarms tab: its label, the time
/// left, and Cancel.
struct TimerSection: View {
    @Bindable var model: AppModel
    var ticking = true

    var body: some View {
        if let endsAt = model.timerEndsAt {
            Section {
                HStack {
                    TimelineView(Ticking.schedule(ticking)) { context in
                        let left = Int(endsAt.timeIntervalSince(context.date).rounded(.up))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.timerLabel).font(.headline)
                            Text(left > 0 ? TimerLength.clock(left) : "Ringing")
                                .font(.title2.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("timer-row")
                    }
                    Spacer()
                    Button("Cancel", role: .destructive) { Task { await model.cancelTimer() } }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("cancel-timer")
                }
            }
        }
    }
}
