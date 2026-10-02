import AlarmCore
import SwiftUI

/// The Clock app's alarm list: every routine with its time, label, days
/// and an on/off switch. Tap one to edit it, swipe to delete, + to add.
struct RoutinesView: View {
    @Bindable var model: AppModel
    @State private var adding = false
    @State private var editing: Routine?
    @State private var settings = false
    var onScreen = true

    var body: some View {
        NavigationStack {
            List {
                PermissionSection(model: model)
                if let error = model.routineError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("routine-error")
                    }
                }
                if model.waitingRoutineChanges > 0 {
                    Section {
                        Label(
                            "\(model.waitingRoutineChanges) change(s) set on this phone, waiting for a connection to reach abera.tech.",
                            systemImage: "icloud.slash"
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("routines-waiting")
                    }
                }
                if model.routines.isEmpty {
                    Text("No alarms. Tap + to add one.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("no-routines")
                }
                ForEach(model.routines) { routine in
                    RoutineRow(model: model, routine: routine, ticking: onScreen)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = routine }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await model.deleteRoutine(routine) }
                            }
                        }
                }
            }
            .navigationTitle("Alarms")
            .refreshable { await model.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        settings = true
                    } label: {
                        Label("Sound & Snooze", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("sound-settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Label("Add alarm", systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-routine")
                }
            }
            .sheet(isPresented: $adding) {
                RoutineEditor(model: model, routine: nil)
            }
            .sheet(isPresented: $settings) {
                SoundSettingsView(model: model)
            }
            .sheet(item: $editing) { routine in
                RoutineEditor(model: model, routine: routine)
            }
        }
    }
}

struct RoutineRow: View {
    @Bindable var model: AppModel
    let routine: Routine
    var ticking = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(RoutineText.time(hour: routine.hour, minute: routine.minute))
                    .font(.system(size: 44, weight: .light).monospacedDigit())
                Text("\(routine.label), \(routine.daysText)")
                    .font(.subheadline)
                if routine.enabled {
                    TimelineView(Ticking.schedule(ticking)) { context in
                        if let clock = RingClock.text(for: routine, at: context.date) {
                            Text(clock)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("routine-\(routine.label)")
            Spacer()
            Toggle(
                "\(routine.label) on",
                isOn: Binding(
                    get: { routine.enabled },
                    set: { on in Task { await model.setRoutine(routine, enabled: on) } })
            )
            .labelsHidden()
            .accessibilityIdentifier("routine-switch-\(routine.label)")
        }
        .foregroundStyle(routine.enabled ? .primary : .secondary)
    }
}

enum RoutineText {
    /// "5:30 AM" or "05:30", as the phone's settings write a time.
    static func time(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Add or edit a routine: a time wheel, the days it repeats, a label and
/// the snooze length.
struct RoutineEditor: View {
    @Bindable var model: AppModel
    let routine: Routine?
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var days: Set<Int>
    @State private var label: String
    @State private var snoozeMinutes: Int

    init(model: AppModel, routine: Routine?) {
        self.model = model
        self.routine = routine
        let hour = routine?.hour ?? 6
        let minute = routine?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date())
        _days = State(initialValue: Set(routine?.days ?? []))
        _label = State(initialValue: routine?.label == RoutineDraft.defaultLabel ? "" : routine?.label ?? "")
        _snoozeMinutes = State(initialValue: routine?.snoozeMinutes ?? 9)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("routine-time")
                Section {
                    DayButtons(days: $days)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(
                        days.isEmpty
                            ? "No repeat. It rings on the next day at this time until you stop it, then switches off."
                            : "Repeats: \(Routine.daysText(Array(days))). It rings until you stop it."
                    )
                    .accessibilityIdentifier("repeat-note")
                }
                Section {
                    TextField("Label", text: $label, prompt: Text(RoutineDraft.defaultLabel))
                        .accessibilityIdentifier("routine-label")
                    Stepper("Snooze: \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...30)
                }
                if let routine {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            Task {
                                await model.deleteRoutine(routine)
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("delete-routine")
                    }
                }
                if let error = model.routineError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(routine == nil ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.saveRoutine(id: routine?.id, draft) { dismiss() }
                        }
                    }
                    .disabled(!draft.problems.isEmpty || model.busy)
                    .accessibilityIdentifier("save-routine")
                }
            }
            .onAppear { model.clearRoutineError() }
        }
    }

    private var draft: RoutineDraft {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return RoutineDraft(
            label: label, hour: parts.hour ?? 0, minute: parts.minute ?? 0, days: days.sorted(),
            enabled: routine?.enabled ?? true, snoozeMinutes: snoozeMinutes)
    }
}

/// Seven round buttons, Monday to Sunday, as ISO weekdays 1 to 7.
struct DayButtons: View {
    @Binding var days: Set<Int>
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Self.letters[day - 1])
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.names[day - 1])
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityIdentifier("day-\(day)")
                if day < 7 { Spacer(minLength: 0) }
            }
        }
    }
}
