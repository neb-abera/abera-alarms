import AlarmCore
import SwiftUI

/// Every countdown on abera.tech, each with a clock that ticks once a
/// second. abera.tech puts each on Google Calendar, and one with its alarm
/// on rings at its target. Tap one to edit it, swipe to delete, + to add.
struct CountdownsView: View {
    @Bindable var model: AppModel
    @State private var adding = false
    @State private var editing: Countdown?
    @State private var deleting: Countdown?
    var onScreen = true

    var body: some View {
        NavigationStack {
            List {
                if let error = model.countdownError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("countdown-error")
                    }
                }
                if model.countdowns.isEmpty {
                    Text("No countdowns. Tap + to add one.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("no-countdowns")
                }
                ForEach(model.countdowns) { countdown in
                    CountdownRow(countdown: countdown, ticking: onScreen)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = countdown }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = countdown }
                        }
                }
            }
            .navigationTitle("Countdowns")
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Label("Add countdown", systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-countdown")
                }
            }
            .sheet(isPresented: $adding) {
                CountdownEditor(model: model, countdown: nil)
            }
            .sheet(item: $editing) { countdown in
                CountdownEditor(model: model, countdown: countdown)
            }
            .confirmDelete($deleting, model: model)
        }
    }
}

extension View {
    /// Asks before a countdown is deleted, from a swipe or the editor.
    func confirmDelete(_ countdown: Binding<Countdown?>, model: AppModel, then done: @escaping () -> Void = {})
        -> some View
    {
        confirmationDialog(
            "Delete \(countdown.wrappedValue?.label ?? "this countdown")?",
            isPresented: Binding(
                get: { countdown.wrappedValue != nil }, set: { if !$0 { countdown.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: countdown.wrappedValue
        ) { target in
            Button("Delete Countdown", role: .destructive) {
                Task {
                    if await model.deleteCountdown(target) { done() }
                }
            }
            .accessibilityIdentifier("confirm-delete-countdown")
        } message: { _ in
            Text("It is deleted on abera.tech and every paired phone.")
        }
    }
}

/// The clocks on a tab tick once a second while it is the selected tab. A
/// TabView keeps the other tabs' views, so their clocks wait a day instead.
/// The selection decides, not onAppear: on iOS 27 a sheet's appear and
/// disappear left a visible list marked as hidden.
enum Ticking {
    static func schedule(_ onScreen: Bool) -> PeriodicTimelineSchedule {
        .periodic(from: .now, by: onScreen ? 1 : 86_400)
    }
}

struct CountdownRow: View {
    let countdown: Countdown
    var ticking = true

    var body: some View {
        TimelineView(Ticking.schedule(ticking)) { context in
            let remaining = countdown.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                Text(countdown.label)
                    .font(.headline)
                Text(remaining.text)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(remaining.passed ? .secondary : .primary)
                Text(countdown.targetText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if countdown.alarm {
                    Label("Alarm at this time", systemImage: "alarm")
                        .font(.footnote)
                }
                if countdown.onCalendar == false {
                    Text("Not on the calendar yet. Edit and save it to add it.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("countdown-\(countdown.label)")
        }
    }
}

/// Add or edit a countdown: a label, a date and time, the zone the time is
/// in, and whether it rings. A new one starts in the phone's zone, or New
/// York when the phone's zone has no tz database name. An edit keeps its own.
struct CountdownEditor: View {
    @Bindable var model: AppModel
    let countdown: Countdown?
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var target: Date
    @State private var zone: String
    @State private var alarm: Bool
    @State private var deleting: Countdown?

    init(model: AppModel, countdown: Countdown?) {
        self.model = model
        self.countdown = countdown
        let tomorrow = Date().addingTimeInterval(86_400)
        _label = State(initialValue: countdown?.label ?? "")
        _target = State(
            initialValue: countdown?.targetAt
                ?? Date(timeIntervalSinceReferenceDate: (tomorrow.timeIntervalSinceReferenceDate / 60).rounded() * 60))
        _zone = State(initialValue: countdown?.timeZone ?? Zones.phone())
        _alarm = State(initialValue: countdown?.alarm ?? false)
    }

    private var draft: CountdownDraft { CountdownDraft(label: label, targetAt: target, timeZone: zone, alarm: alarm) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label, prompt: Text(CountdownDraft.defaultLabel))
                        .accessibilityIdentifier("countdown-label")
                    DatePicker("Date and time", selection: $target)
                        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                        .accessibilityIdentifier("countdown-target")
                    NavigationLink {
                        ZonePicker(zone: $zone)
                    } label: {
                        LabeledContent("Time zone", value: zone)
                    }
                    .accessibilityIdentifier("countdown-zone")
                } footer: {
                    Text(
                        Countdown(id: UUID(), label: draft.sentLabel, targetAt: target, timeZone: zone).targetText
                    )
                    .accessibilityIdentifier("countdown-target-text")
                }
                Section {
                    Toggle("Alarm at this time", isOn: $alarm)
                        .accessibilityIdentifier("countdown-alarm")
                } footer: {
                    Text(
                        "Rings on the phone and through Pushover until it is stopped. Every countdown is on Google Calendar."
                    )
                }
                ForEach(draft.problems, id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let error = model.countdownError {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("countdown-editor-error")
                }
                if let countdown {
                    Section {
                        Button("Delete Countdown", role: .destructive) { deleting = countdown }
                            .accessibilityIdentifier("delete-countdown")
                    }
                }
            }
            .navigationTitle(countdown == nil ? "Add Countdown" : "Edit Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.saveCountdown(id: countdown?.id, draft) { dismiss() }
                        }
                    }
                    .disabled(!draft.problems.isEmpty || model.busy)
                    .accessibilityIdentifier("save-countdown")
                }
            }
            .confirmDelete($deleting, model: model) { dismiss() }
            .onChange(of: zone) { old, new in target = CountdownDraft.sameWallClock(target, from: old, to: new) }
            .onAppear { model.clearCountdownError() }
        }
    }
}

/// Every zone the tz database knows, searchable by name, the United States
/// first, east to west.
struct ZonePicker: View {
    @Binding var zone: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var zones: [String] { Zones.matching(search) }

    var body: some View {
        let us = Set(Zones.unitedStates)
        List {
            Section("United States") {
                ForEach(zones.filter { us.contains($0) }, id: \.self, content: row)
            }
            Section("Everywhere else") {
                ForEach(zones.filter { !us.contains($0) }, id: \.self, content: row)
            }
        }
        .searchable(text: $search, prompt: "City or region")
        .navigationTitle("Time Zone")
    }

    private func row(_ name: String) -> some View {
        Button {
            zone = name
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if name == zone { Image(systemName: "checkmark") }
            }
        }
        .accessibilityIdentifier("zone-\(name)")
    }
}
