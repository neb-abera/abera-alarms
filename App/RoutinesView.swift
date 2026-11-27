import AlarmCore
import SwiftUI

/// The Clock app's alarm list: every routine with its time, label, days
/// and an on/off switch. Tap one to edit it, + to add. Delete one by a
/// swipe, a press and hold, or Delete Alarm in its editor. Select deletes
/// several, or all of them.
struct RoutinesView: View {
    @Bindable var model: AppModel
    @State private var adding = false
    @State private var editing: Routine?
    @State private var settings = false
    @State private var timer = false
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var confirmingDelete: Set<UUID>?
    @State private var showingHistory = false
    @State private var openedStep: StepOpened?
    @State private var checklist: Routine?
    @State private var moving: Moving?

    struct StepOpened: Identifiable {
        var routine: Routine
        var cycle: RoutineCycle
        var ring: RoutineCycle.StepRing
        var id: String { ring.key }
    }

    /// An alarm about to go under another as a step.
    struct Moving: Identifiable {
        var child: Routine
        var parent: Routine
        var id: String { child.id.uuidString + parent.id.uuidString }
    }
    var onScreen = true

    var body: some View {
        NavigationStack {
            List {
                ReadinessSection(model: model)
                if selecting {
                    Section {
                        HStack {
                            Button("Delete Selected (\(selected.count))", role: .destructive) {
                                confirmingDelete = selected
                            }
                            .buttonStyle(.borderless)
                            .disabled(selected.isEmpty)
                            .accessibilityIdentifier("delete-selected-routines")
                            Spacer()
                            Button("Delete All", role: .destructive) {
                                confirmingDelete = Set(model.routines.map(\.id))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("delete-all-routines")
                        }
                    } footer: {
                        Text("Tap the circles to select alarms.")
                    }
                }
                TimerSection(model: model, ticking: onScreen)
                if !model.blocked, model.testRingsAt != nil || model.testMissed || model.testError != nil {
                    Section("Test alarm") {
                        TestAlarmControls(model: model)
                    }
                }
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
                if model.routines.contains(where: { !$0.steps.isEmpty }) {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("Steps done, last 14 days", systemImage: "calendar.badge.checkmark")
                    }
                    .accessibilityIdentifier("steps-history")
                }
                if model.routines.isEmpty {
                    Text("No alarms. Tap + to add one.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("no-routines")
                }
                ForEach(model.orderedRoutines(at: Date())) { routine in
                    HStack {
                        if selecting {
                            let on = selected.contains(routine.id)
                            Button {
                                if on { selected.remove(routine.id) } else { selected.insert(routine.id) }
                            } label: {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(on ? "Selected \(routine.label)" : "Select \(routine.label)")
                            .accessibilityIdentifier("select-routine-\(routine.label)")
                        }
                        RoutineRow(model: model, routine: routine, ticking: onScreen, selecting: selecting) {
                            editing = routine
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await model.deleteRoutine(routine) }
                        }
                    }
                    // A swipe right shows or hides the alarm's steps.
                    .swipeActions(edge: .leading) {
                        if !routine.steps.isEmpty {
                            let open = model.stepsOpen(routine, at: Date())
                            Button(open ? "Hide Steps" : "Show Steps") {
                                withAnimation(.easeInOut(duration: 0.2)) { model.toggleSteps(routine, at: Date()) }
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = routine }
                        if case .mark(let cycle) = model.ringControl(routine, at: Date()) {
                            Button("Done for \(StepText.when(cycle.at))", systemImage: "checkmark.circle") {
                                Task { await model.mark(routine, cycle: cycle, .done) }
                            }
                            Button("Skip \(StepText.when(cycle.at))", systemImage: "forward") {
                                Task { await model.mark(routine, cycle: cycle, .skipped) }
                            }
                        }
                        // An alarm that repeats by interval has no time of day to keep as a step.
                        let others = model.routines.filter { $0.id != routine.id && RoutineChaining.canChain($0) }
                        if !RoutineChaining.canChain(routine) {
                            Button(RoutineChaining.intervalReason, systemImage: "arrow.turn.down.right") {}
                                .disabled(true)
                                .accessibilityIdentifier("make-step-blocked")
                        } else if !others.isEmpty {
                            Menu("Make a Step of…", systemImage: "arrow.turn.down.right") {
                                ForEach(others) { parent in
                                    Button(
                                        "\(parent.label), \(RoutineText.time(hour: parent.hour, minute: parent.minute))"
                                    ) {
                                        moving = Moving(child: routine, parent: parent)
                                    }
                                }
                            }
                            .accessibilityIdentifier("make-step-of")
                        }
                        if !routine.steps.isEmpty {
                            Button("Steps, This Time and Next", systemImage: "checklist") { checklist = routine }
                                .accessibilityIdentifier("open-checklist")
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.deleteRoutine(routine) }
                        }
                        .accessibilityIdentifier("context-delete")
                    }
                    if !selecting, let control = model.ringControl(routine, at: Date()) {
                        RingControlRow(model: model, routine: routine, control: control)
                    }
                    if !selecting, !routine.steps.isEmpty {
                        let open = model.stepsOpen(routine, at: Date())
                        StepsToggleRow(model: model, routine: routine, open: open)
                        if open {
                            StepRows(model: model, routine: routine, ticking: onScreen) { cycle, ring in
                                openedStep = StepOpened(routine: routine, cycle: cycle, ring: ring)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alarms")
            .refreshable { await model.sync() }
            .toolbar {
                // Scrolled, the title squeezed between the buttons read "Al..."
                // (Neb's iPhone, 2026-11-21). The tab bar names the page.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selected = []
                    }
                    .disabled(model.routines.isEmpty && !selecting)
                    .accessibilityIdentifier("select-routines")
                }
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
                        timer = true
                    } label: {
                        Label("Timer", systemImage: "timer")
                    }
                    .accessibilityIdentifier("new-timer")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.ringTestAlarm() }
                    } label: {
                        Label("Ring a test alarm", systemImage: "bell.and.waves.left.and.right")
                    }
                    .accessibilityIdentifier("test-alarm")
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
            .confirmationDialog(
                confirmingDelete.map { $0.count == 1 ? "Delete 1 alarm?" : "Delete \($0.count) alarms?" } ?? "",
                isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
                titleVisibility: .visible,
                presenting: confirmingDelete
            ) { ids in
                Button(ids.count == 1 ? "Delete Alarm" : "Delete \(ids.count) Alarms", role: .destructive) {
                    Task {
                        await model.deleteRoutines(ids)
                        selected = []
                        selecting = false
                    }
                }
                .accessibilityIdentifier("confirm-delete-routines")
            } message: { _ in
                Text("They are deleted on this phone and on abera.tech.")
            }
            .sheet(isPresented: $timer) {
                TimerSheet(model: model)
            }
            .sheet(isPresented: $adding) {
                RoutineEditor(model: model, routine: nil)
            }
            .sheet(isPresented: $settings) {
                SoundSettingsView(model: model)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView(model: model)
            }
            .sheet(item: $openedStep) { opened in
                CompletionSheet(model: model, routine: opened.routine, cycle: opened.cycle, ring: opened.ring)
            }
            .navigationDestination(item: $checklist) { routine in
                ChecklistView(model: model, routineID: routine.id)
            }
            .confirmationDialog(
                moving.map { "Make \($0.child.label) a step of \($0.parent.label)?" } ?? "",
                isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
                titleVisibility: .visible,
                presenting: moving
            ) { move in
                Button("Make It a Step") {
                    Task { await model.subordinate(move.child, under: move.parent) }
                }
                .accessibilityIdentifier("confirm-make-step")
            } message: { move in
                Text(
                    "It rings at \(RoutineText.time(hour: move.child.hour, minute: move.child.minute)) as a step of \(move.parent.label), on \(move.parent.label)'s days: \(move.parent.repeatText). It is no longer an alarm of its own. Separate it to undo."
                )
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
    var selecting = false
    var open: () -> Void = {}

    var body: some View {
        HStack {
            // The tap that opens the editor covers the text and the space
            // beside it, never the switch. On the whole row, iOS 27 sent
            // some taps on the switch to the editor instead.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RoutineText.time(hour: routine.hour, minute: routine.minute))
                        .font(.system(size: 44, weight: .light).monospacedDigit())
                    Text("\(routine.label), \(routine.repeatText)")
                        .font(.subheadline)
                    if let status = model.syncStatus(routine) {
                        RoutineSyncLine(status: status)
                            .accessibilityIdentifier("routine-sync-\(routine.label)")
                    } else if routine.enabled {
                        TimelineView(Ticking.schedule(ticking)) { context in
                            let state = model.state ?? AlertsState()
                            if let clock = RingClock.text(for: routine, in: state, at: context.date) {
                                // A ring that has rung with steps left is orange, with Rang beside it.
                                let rang =
                                    AlarmList.underWay(routine, in: state, now: context.date, calendar: .current)
                                    != nil
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    if rang { StatusTag(status: .rang) }
                                    Text(clock)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(rang ? Color.orange : Color.secondary)
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("routine-\(routine.label)")
                Spacer()
            }
            .contentShape(Rectangle())
            // While selecting, the circle beside the row selects it, and the editor stays shut.
            .onTapGesture { if !selecting { open() } }
            .allowsHitTesting(!selecting)
            Toggle(
                "\(routine.label) on",
                isOn: Binding(
                    get: { routine.enabled },
                    set: { on in Task { await model.setRoutine(routine, enabled: on) } })
            )
            .labelsHidden()
            .disabled(selecting)
            .accessibilityIdentifier("routine-switch-\(routine.label)")
        }
        .foregroundStyle(routine.enabled ? .primary : .secondary)
        .animation(.easeInOut(duration: 0.2), value: model.syncStatus(routine))
    }
}

/// One small line under a routine while its change travels to abera.tech.
struct RoutineSyncLine: View {
    let status: RoutineSyncStatus

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: status == .sending)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch status {
        case .sending: "Set on this phone. Sending to abera.tech."
        case .waiting: "Set on this phone. Sends when online."
        case .saved: "Saved to abera.tech."
        }
    }

    private var symbol: String {
        switch status {
        case .sending: "arrow.triangle.2.circlepath.icloud"
        case .waiting: "icloud.slash"
        case .saved: "checkmark.icloud"
        }
    }

    private var color: Color {
        switch status {
        case .sending: .secondary
        case .waiting: .orange
        case .saved: .green
        }
    }
}

enum RoutineText {
    /// "5:30 AM" or "05:30", as the phone's settings write a time.
    static func time(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Add or edit a routine: a time wheel, how it repeats, a label and the
/// snooze length. It repeats on days of the week, every N weeks on those
/// days, or every N minutes, hours, days, weeks, months, or years from a
/// start date. Neb asked on 2026-11-25 for a number and a unit: he could not
/// set an alarm for every 97 minutes, or every other week.
struct RoutineEditor: View {
    /// What the Repeat menu shows.
    enum RepeatChoice: Hashable {
        case once, weekdays, interval
    }

    @Bindable var model: AppModel
    let routine: Routine?
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var choice: RepeatChoice
    /// Weeks between ring weeks, for days of the week. 0 while the field is empty.
    @State private var weeks: Int
    /// The N of an interval. 0 while the field is empty.
    @State private var every: Int
    @State private var unit: RoutineUnit
    @State private var starts: Date
    @State private var days: Set<Int>
    @State private var label: String
    @State private var snoozeMinutes: Int
    @State private var steps: [EditableStep]
    @State private var absorbed: [Routine] = []
    @State private var stepRefusal: String?

    init(model: AppModel, routine: Routine?) {
        self.model = model
        self.routine = routine
        let hour = routine?.hour ?? 6
        let minute = routine?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date())
        _days = State(initialValue: Set(routine?.days ?? []))
        let interval = routine?.repeatMode == .interval
        let choice: RepeatChoice = interval ? .interval : (routine?.days.isEmpty ?? true) ? .once : .weekdays
        _choice = State(initialValue: choice)
        _weeks = State(initialValue: interval ? 1 : max(routine?.every ?? 1, 1))
        _every = State(initialValue: interval ? routine?.every ?? 1 : 1)
        _unit = State(initialValue: interval ? routine?.unit ?? .hours : .hours)
        _starts = State(
            initialValue: Self.date(of: routine?.startsOn) ?? Calendar.current.startOfDay(for: Date()))
        _label = State(initialValue: routine?.label == RoutineDraft.defaultLabel ? "" : routine?.label ?? "")
        _snoozeMinutes = State(initialValue: routine?.snoozeMinutes ?? 9)
        _steps = State(initialValue: routine?.steps.map(EditableStep.init) ?? [])
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
                    Picker("Repeats", selection: $choice) {
                        Text("No repeat").tag(RepeatChoice.once)
                        Text("Days of the week").tag(RepeatChoice.weekdays)
                        Text("Every…").tag(RepeatChoice.interval)
                    }
                    .accessibilityIdentifier("routine-repeat")
                    // The days stay in reach with no repeat chosen: one tap on a day sets a weekly alarm.
                    if choice != .interval {
                        DayButtons(days: $days)
                    }
                    if choice == .weekdays {
                        EveryRow(amount: $weeks, id: "routine-weeks") {
                            Text(RoutineUnit.weeks.name(weeks))
                        }
                    }
                    if choice == .interval {
                        EveryRow(amount: $every, id: "routine-every") {
                            Picker("Unit", selection: $unit) {
                                ForEach(RoutineUnit.allCases, id: \.self) { unit in
                                    Text(unit.name(every)).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("routine-every-unit")
                        }
                    }
                    if choice == .interval || (choice == .weekdays && weeks > 1) {
                        // Side by side, or the date under its word when the text is large.
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("Starting")
                                Spacer(minLength: 8)
                                startPicker
                            }
                            VStack(alignment: .leading) {
                                Text("Starting")
                                startPicker
                            }
                        }
                    }
                    ForEach(draft.repeatProblems, id: \.self) { problem in
                        Text(problem).foregroundStyle(.red)
                    }
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(draft.repeatNote(today: CivilDate(Date(), in: .current)))
                        .accessibilityIdentifier("repeat-note")
                }
                Section {
                    TextField("Label", text: $label, prompt: Text(RoutineDraft.defaultLabel))
                        .accessibilityIdentifier("routine-label")
                    Stepper("Snooze: \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...30)
                }
                StepsEditorSection(
                    steps: $steps, routineLabel: label,
                    existing: chainable, addExisting: absorb, absorbed: absorbed,
                    existingNote: chainingNote)
                if let stepRefusal {
                    Text(stepRefusal).foregroundStyle(.red)
                }
                ForEach(RoutineStep.problems(steps.map(\.step)), id: \.self) { problem in
                    Text(problem).foregroundStyle(.red)
                }
                if let routine {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            Task { await model.deleteRoutine(routine) }
                            dismiss()
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
                        let draft = draft
                        let absorbed = absorbed
                        Task {
                            // The picked alarms go only once their steps are saved.
                            guard await model.saveRoutine(id: routine?.id, draft) else { return }
                            for alarm in absorbed { await model.deleteRoutine(alarm) }
                        }
                        dismiss()
                    }
                    .disabled(!draft.problems.isEmpty)
                    .accessibilityIdentifier("save-routine")
                }
            }
            .onAppear { model.clearRoutineError() }
            // A day tapped with no repeat chosen makes it days of the week.
            // The last day taken off makes it no repeat again.
            .onChange(of: days) { _, chosen in
                if choice == .once, !chosen.isEmpty { choice = .weekdays }
                if choice == .weekdays, chosen.isEmpty { choice = .once }
            }
            .onChange(of: choice) { _, chosen in
                if chosen == .once, !days.isEmpty { days = [] }
            }
        }
    }

    /// The alarms that can be added as steps: none while this one repeats
    /// by interval, and never one that does.
    private var chainable: [Routine] {
        guard choice != .interval else { return [] }
        return model.routines.filter { alarm in
            alarm.id != routine?.id && RoutineChaining.canChain(alarm)
                && !absorbed.contains(where: { $0.id == alarm.id })
        }
    }

    /// Why no existing alarm is offered as a step, when there is one to offer.
    private var chainingNote: String? {
        guard choice == .interval, model.routines.contains(where: { $0.id != routine?.id }) else { return nil }
        return RoutineChaining.intervalReason
    }

    private var startPicker: some View {
        DatePicker("Starting", selection: $starts, displayedComponents: .date)
            .labelsHidden()
            .accessibilityIdentifier("routine-starts")
    }

    /// Midnight on a "yyyy-MM-dd" date in the phone's zone. Nil when it is not one.
    private static func date(of text: String?) -> Date? {
        guard let text, let day = CivilDate(iso: text) else { return nil }
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }

    /// Puts an existing alarm into the steps at the time it rings.
    private func absorb(_ alarm: Routine) {
        let current = self.draft
        let shape = Routine(
            id: routine?.id ?? UUID(), label: label, hour: current.hour, minute: current.minute, days: current.days,
            steps: steps.map(\.step), repeatMode: current.repeatMode, every: current.every, unit: current.unit,
            startsOn: current.startsOn)
        switch RoutineChaining.subordinate(alarm, under: shape) {
        case .success(let made):
            steps = made.steps.map(EditableStep.init)
            absorbed.append(alarm)
            stepRefusal = nil
        case .failure(let refusal):
            stepRefusal = refusal.message
        }
    }

    private var draft: RoutineDraft {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var draft = RoutineDraft(
            label: label, hour: parts.hour ?? 0, minute: parts.minute ?? 0, days: [],
            enabled: routine?.enabled ?? true, snoozeMinutes: snoozeMinutes, steps: steps.map(\.step))
        let start = CivilDate(starts, in: .current).iso
        // A day just tapped counts at once, before the menu follows it.
        let shown: RepeatChoice = choice == .once && !days.isEmpty ? .weekdays : choice
        switch shown {
        case .once:
            break
        case .weekdays:
            draft.days = days.sorted()
            draft.every = weeks
            draft.startsOn = weeks > 1 ? start : nil
        case .interval:
            draft.repeatMode = .interval
            draft.every = every
            draft.unit = unit
            draft.startsOn = start
        }
        return draft
    }
}

/// "Every", a typed number, and its unit: "Every 97 minutes". On one line,
/// or the number and unit under the word when the text is large.
struct EveryRow<Trailing: View>: View {
    @Binding var amount: Int
    let id: String
    let unit: Trailing
    /// Wide enough for 999 at the text size in use.
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 64

    init(amount: Binding<Int>, id: String, @ViewBuilder unit: () -> Trailing) {
        _amount = amount
        self.id = id
        self.unit = unit()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("Every")
                field
                unit
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading) {
                Text("Every")
                HStack {
                    field
                    unit
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // An empty field shows a grey 0, so a typed number replaces it.
    private var field: some View {
        TextField(
            "Every",
            text: Binding(
                get: { amount == 0 ? "" : String(amount) },
                set: { amount = min(TimeSpan.amount(typed: $0), 9999) }),
            prompt: Text("0")
        )
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.roundedBorder)
        .frame(width: fieldWidth)
        .accessibilityIdentifier("\(id)-amount")
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
