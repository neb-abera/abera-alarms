import AlarmCore
import SwiftUI
import UIKit

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if !model.started {
                ProgressView()
            } else if model.paired {
                AlarmsView(model: model)
            } else {
                PairView(model: model)
            }
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

    var body: some View {
        NavigationStack {
            List {
                PermissionSection(model: model)
                StatusSection(model: model)
                Section {
                    Picker("Show", selection: $model.showAll) {
                        Text("Alarms").tag(false)
                        Text("All events").tag(true)
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
                            EventRow(model: model, alert: alert)
                        }
                    }
                }
                Section {
                } footer: {
                    Footer(model: model)
                }
            }
            .navigationTitle("Alarms")
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingEvent = true
                    } label: {
                        Label("New event", systemImage: "plus")
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
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alarm-\(alert.key)")
            Spacer()
            TypeMenu(model: model, alert: alert)
        }
        .swipeActions {
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
            return alert.acknowledgedVia == "browser" ? "Acknowledged in a browser" : "Acknowledged on a phone"
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
                Label("Alarm", systemImage: "alarm")
            }
            Button {
                Task { await model.setType(alert, AlertType.notification) }
            } label: {
                Label("Notification", systemImage: "bell")
            }
            Button {
                Task { await model.setType(alert, AlertType.none) }
            } label: {
                Label("None", systemImage: "bell.slash")
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
        case AlertType.alarm: "Alarm"
        case AlertType.notification: "Notification"
        default: "None"
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

// MARK: New event

struct NewEventView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt = NewEventView.nextHalfHour()
    @State private var durationMinutes = 30
    @State private var location = ""
    @State private var type = AlertType.alarm
    @State private var leadMinutes = 10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("event-title")
                    DatePicker("Starts", selection: $startsAt, in: Date()...)
                        .accessibilityIdentifier("event-start")
                    Stepper("Length: \(durationMinutes) min", value: $durationMinutes, in: 5...1440, step: 5)
                    TextField("Location (optional)", text: $location)
                }
                Section {
                    Picker("Type", selection: $type) {
                        Text("Alarm").tag(AlertType.alarm)
                        Text("Notification").tag(AlertType.notification)
                        Text("None").tag(AlertType.none)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("event-type")
                    if type != AlertType.none {
                        Stepper("Alert \(leadMinutes) min before", value: $leadMinutes, in: 0...1440, step: 5)
                    }
                } footer: {
                    Text(
                        "abera.tech adds the event to your Google Calendar. An alarm gets #critical in its description."
                    )
                }
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
            .navigationTitle("New event")
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
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !problems.isEmpty || model.busy)
                    .accessibilityIdentifier("add-event")
                }
            }
            .onAppear { model.clearEventError() }
        }
    }

    private var event: NewEvent {
        NewEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: startsAt,
            durationMinutes: durationMinutes,
            location: location.isEmpty ? nil : location, type: type,
            leadMinutes: type == AlertType.none ? nil : leadMinutes)
    }

    private var problems: [String] {
        title.isEmpty ? [] : event.problems(now: Date())
    }

    /// The first half hour at least 20 minutes away, so a default alert of 10
    /// minutes before is still ahead.
    static func nextHalfHour(after now: Date = Date()) -> Date {
        let now = now.addingTimeInterval(20 * 60)
        let seconds = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 1800).rounded(.up) * 1800)
    }
}

struct PermissionSection: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.permission {
        case .allowed:
            EmptyView()
        case .notAsked:
            Section {
                Text("This app needs permission to ring alarms.")
                Button("Allow alarms") { Task { await model.requestPermission() } }
                    .accessibilityIdentifier("allow-alarms")
            }
        case .denied:
            Section {
                Text("Alarms are off for this app. Nothing will ring on this phone.")
                    .foregroundStyle(.red)
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        }
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
            Text("Tap the icon beside an event to make it an alarm. Swipe to skip one day. Pull down to sync.")
        }
    }
}
