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

    var body: some View {
        NavigationStack {
            List {
                PermissionSection(model: model)
                StatusSection(model: model)
                Section {
                    if model.alarms.isEmpty {
                        Text("No alarms in the next 48 hours.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("no-alarms")
                    }
                    ForEach(model.alarms) { alert in
                        AlarmRow(alert: alert, held: model.isHeld(alert))
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
                } header: {
                    Text("Alarms")
                } footer: {
                    Footer(model: model)
                }
            }
            .navigationTitle("Alarms")
            .refreshable { await model.sync() }
            .toolbar {
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
            .confirmationDialog("Unpair this phone?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
                Button("Unpair and remove its alarms", role: .destructive) { Task { await model.unpair() } }
            } message: {
                Text("The phone stops ringing. Revoke its token on abera.tech/alerts too.")
            }
        }
    }
}

struct AlarmRow: View {
    let alert: Alert
    let held: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.title).font(.headline)
            Text(
                "Rings \(alert.alertAt, format: .dateTime.weekday().hour().minute()), starts \(alert.startsAt, format: .dateTime.hour().minute())"
            )
            .font(.subheadline)
            if let location = alert.location, !location.isEmpty {
                Text(location).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(status).font(.caption).foregroundStyle(statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alarm-\(alert.key)")
    }

    private var status: String {
        if alert.acknowledged {
            return alert.acknowledgedVia == "browser" ? "Acknowledged in a browser" : "Acknowledged on a phone"
        }
        if alert.skipped { return "Skipped" }
        if alert.muted { return "Muted" }
        return held ? "Set on this phone" : "Not set on this phone"
    }

    private var statusColor: Color {
        if alert.acknowledged || alert.skipped || alert.muted { return .secondary }
        return held ? .green : .red
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
            Text("Swipe an alarm to skip it. Pull down to sync.")
        }
    }
}
