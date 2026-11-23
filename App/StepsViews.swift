import AlarmCore
import PhotosUI
import SwiftUI
import UIKit

/// The steps of a routine in its editor: each with a label and its time
/// after the item before it, typed as a number with its unit.
struct StepsEditorSection: View {
    @Binding var steps: [EditableStep]
    let routineLabel: String
    /// Alarms that can be made steps of this one, and what to do with one picked.
    var existing: [Routine] = []
    var addExisting: (Routine) -> Void = { _ in }
    /// Alarms picked here, deleted as alarms on Save.
    var absorbed: [Routine] = []

    var body: some View {
        Section {
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Step", text: $step.label, prompt: Text(RoutineStep.defaultLabel))
                        .accessibilityIdentifier("step-label-\(index(of: step))")
                    SpanField(
                        title: "After \(previousLabel(before: step))", span: $step.after,
                        id: "step-after-\(index(of: step))")
                }
            }
            .onDelete { steps.remove(atOffsets: $0) }
            .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            Button {
                steps.append(EditableStep(label: "", after: TimeSpan(5, .minutes)))
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
            .disabled(steps.count >= RoutineStep.maxSteps)
            .accessibilityIdentifier("add-step")
            if !existing.isEmpty {
                Menu {
                    ForEach(existing) { alarm in
                        Button("\(alarm.label), \(RoutineText.time(hour: alarm.hour, minute: alarm.minute))") {
                            addExisting(alarm)
                        }
                    }
                } label: {
                    Label("Add an Existing Alarm as a Step", systemImage: "arrow.turn.down.right")
                }
                .disabled(steps.count >= RoutineStep.maxSteps)
                .accessibilityIdentifier("add-existing-step")
            }
            ForEach(absorbed) { alarm in
                Text("\(alarm.label) becomes a step at its own time and stops being an alarm of its own when you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Steps")
        } footer: {
            Text(
                steps.isEmpty
                    ? "A step rings after the alarm, such as Take medication 5 minutes later. Check one off and it does not ring that day. The next day every step is set again."
                    : "Each step rings its time after the one above it. Check one off and it does not ring until the next time the alarm rings. Swipe to delete a step."
            )
        }
    }

    private func index(of step: EditableStep) -> Int {
        steps.firstIndex { $0.id == step.id } ?? 0
    }

    private func previousLabel(before step: EditableStep) -> String {
        let at = index(of: step)
        guard at > 0 else { return routineLabel.isEmpty ? RoutineDraft.defaultLabel : routineLabel }
        let previous = steps[at - 1].label.trimmingCharacters(in: .whitespaces)
        return previous.isEmpty ? RoutineStep.defaultLabel : previous
    }
}

/// A step as the editor holds it, with its offset as a typed span.
struct EditableStep: Identifiable, Equatable {
    var id = UUID()
    var label: String
    var after: TimeSpan

    init(label: String, after: TimeSpan) {
        self.label = label
        self.after = after
    }

    init(_ step: RoutineStep) {
        id = step.id
        label = step.label
        after = TimeSpan(minutes: step.offsetMinutes)
    }

    var step: RoutineStep {
        RoutineStep(id: id, label: label, offsetMinutes: min(after.minutes, RoutineStep.maxOffsetMinutes + 1))
    }
}

/// Under an alarm on the Alarms tab: Done and Skip for its coming ring,
/// each one tap, or the mark on a ring with Undo. Done keeps that ring from
/// sounding. Skip keeps its steps from ringing too. The next ring is set.
struct RingControlRow: View {
    @Bindable var model: AppModel
    let routine: Routine
    let control: AppModel.RingControl

    var body: some View {
        switch control {
        case .mark(let cycle):
            // The words never wrap. At a large text size the time moves above
            // the buttons. "Done" broke into "Don" and "e" on Neb's iPhone
            // (2026-11-21), where the text is larger than the simulator's.
            ViewThatFits(in: .horizontal) {
                HStack {
                    time(cycle)
                    Spacer()
                    buttons(cycle)
                }
                VStack(alignment: .leading, spacing: 8) {
                    time(cycle)
                    HStack { buttons(cycle) }
                }
            }
            .padding(.leading, 20)
        case .marked(let cycle, let outcome):
            HStack {
                Label(
                    outcome.status == .done
                        ? "Done for \(StepText.when(cycle.at))" : "Skipped \(StepText.when(cycle.at))",
                    systemImage: outcome.status == .done ? "checkmark.circle.fill" : "forward.fill"
                )
                .font(.subheadline)
                .foregroundStyle(outcome.status == .done ? Color.green : Color.orange)
                // One element. iOS 26.5 read the icon apart, as "Selected" (CI, 2026-11-21).
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ring-mark-\(routine.label)")
                Spacer()
                Button {
                    Task { await model.unmark(routine, cycle: cycle) }
                } label: {
                    Text("Undo").lineLimit(1).fixedSize()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("ring-undo-\(routine.label)")
            }
            .padding(.leading, 20)
        }
    }
}

extension RingControlRow {
    fileprivate func time(_ cycle: RoutineCycle) -> some View {
        Text(StepText.when(cycle.at))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    fileprivate func buttons(_ cycle: RoutineCycle) -> some View {
        // Words alone, which a button never trades for its icon. Build 234
        // showed Done and Skip as icons only on Neb's iPhone (2026-11-21).
        Button {
            Task { await model.mark(routine, cycle: cycle, .done) }
        } label: {
            Text("Done")
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .accessibilityIdentifier("ring-done-\(routine.label)")
        Button {
            Task { await model.mark(routine, cycle: cycle, .skipped) }
        } label: {
            Text("Skip")
                .fontWeight(.semibold)
                .foregroundStyle(Color.orange)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .accessibilityIdentifier("ring-skip-\(routine.label)")
    }
}

/// A routine's steps, indented under it on the Alarms tab, for the time
/// under way, or the next time once its steps have rung out. The circle
/// checks a step off in one tap. A tap on the step adds a note or a photo.
/// A swipe separates it into an alarm of its own, or deletes it.
struct StepRows: View {
    @Bindable var model: AppModel
    let routine: Routine
    var ticking = true
    let open: (RoutineCycle, RoutineCycle.StepRing) -> Void

    /// Each step is its own row, so each swipes on its own. Only the time
    /// line under a step ticks.
    var body: some View {
        if let cycle = model.shownCycle(routine, at: Date()) {
            ForEach(cycle.steps) { ring in
                row(cycle, ring)
            }
        }
    }

    private func row(_ cycle: RoutineCycle, _ ring: RoutineCycle.StepRing) -> some View {
        let done = model.completion(routine, ring)
        return HStack(alignment: .top) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Button {
                Task {
                    if done == nil {
                        await model.completeStep(routine, cycle: cycle, step: ring.step)
                    } else {
                        await model.undoStep(routine, cycle: cycle, step: ring.step)
                    }
                }
            } label: {
                Image(systemName: done == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(done == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(done == nil ? "Check off \(ring.step.label)" : "Undo \(ring.step.label)")
            .accessibilityIdentifier("check-\(ring.step.label)-\(cycle.stamp)")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ring.step.label)
                        .strikethrough(done != nil)
                    TimelineView(Ticking.schedule(ticking)) { context in
                        Text(StepText.line(ring: ring, done: done, now: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("step-\(ring.step.label)-\(cycle.stamp)")
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { open(cycle, ring) }
        }
        .padding(.leading, 20)
        .foregroundStyle(routine.enabled ? .primary : .secondary)
        .swipeActions {
            Button("Delete", role: .destructive) {
                Task { await model.deleteStep(ring.step, from: routine) }
            }
            Button("Separate") {
                Task { await model.separate(ring.step, from: routine) }
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Note or Photo", systemImage: "square.and.pencil") { open(cycle, ring) }
            Button("Make a Separate Alarm", systemImage: "arrow.uturn.left") {
                Task { await model.separate(ring.step, from: routine) }
            }
            .accessibilityIdentifier("separate-step")
            Button("Delete Step", systemImage: "trash", role: .destructive) {
                Task { await model.deleteStep(ring.step, from: routine) }
            }
        }
    }
}

/// A routine's steps for the cycle under way and the next one. The circle
/// checks a step off in one tap. A tap on the step adds a note or a photo.
struct ChecklistView: View {
    @Bindable var model: AppModel
    let routineID: UUID
    @State private var opened: Opened?

    struct Opened: Identifiable {
        var cycle: RoutineCycle
        var ring: RoutineCycle.StepRing
        var id: String { ring.key }
    }

    private var routine: Routine? { model.routines.first { $0.id == routineID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                if let routine {
                    let cycles = RoutineCycle.around(routine, now: context.date, calendar: .current)
                    if let current = cycles.current {
                        section(routine, current, title: "This time", now: context.date)
                    }
                    if let next = cycles.next {
                        section(routine, next, title: "Next time", now: context.date)
                    }
                    if model.waitingCompletions > 0 {
                        Label(
                            "\(model.waitingCompletions) check-off(s) set on this phone, waiting for a connection to reach abera.tech.",
                            systemImage: "icloud.slash"
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("completions-waiting")
                    }
                    if let error = model.stepError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("step-error")
                    }
                } else {
                    Text("This alarm was deleted.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(routine?.label ?? "Steps")
        .refreshable { await model.sync() }
        .sheet(item: $opened) { opened in
            if let routine {
                CompletionSheet(model: model, routine: routine, cycle: opened.cycle, ring: opened.ring)
            }
        }
    }

    @ViewBuilder
    private func section(_ routine: Routine, _ cycle: RoutineCycle, title: String, now: Date) -> some View {
        Section {
            ForEach(cycle.steps) { ring in
                let done = model.completion(routine, ring)
                HStack(alignment: .top) {
                    Button {
                        Task {
                            if done == nil {
                                await model.completeStep(routine, cycle: cycle, step: ring.step)
                            } else {
                                await model.undoStep(routine, cycle: cycle, step: ring.step)
                            }
                        }
                    } label: {
                        Image(systemName: done == nil ? "circle" : "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(done == nil ? Color.secondary : Color.green)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(done == nil ? "Check off \(ring.step.label)" : "Undo \(ring.step.label)")
                    .accessibilityIdentifier("check-\(ring.step.label)-\(cycle.stamp)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ring.step.label)
                            .strikethrough(done != nil)
                        Text(StepText.line(ring: ring, done: done, now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("step-\(ring.step.label)-\(cycle.stamp)")
                    Spacer()
                    Image(systemName: "square.and.pencil").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { opened = Opened(cycle: cycle, ring: ring) }
            }
        } header: {
            Text("\(title): \(routine.label) at \(StepText.when(cycle.at))")
        }
    }
}

enum StepText {
    /// "Thu 6:00 AM".
    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "today at 21:31", "tomorrow at 07:05", "Tue 24 Nov at 21:31".
    static func on(_ date: Date, now: Date) -> String {
        "\(RingDay.word(date, now: now, calendar: .current)) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    static func line(ring: RoutineCycle.StepRing, done: RoutineCompletion?, now: Date) -> String {
        if let done {
            return "Done \(on(done.completedAt, now: now)). Does not ring \(on(ring.at, now: now))."
        }
        return ring.at > now ? "Rings \(on(ring.at, now: now))" : "Rang \(on(ring.at, now: now)), not checked off"
    }
}

/// Checks a step off with a note and a photo, to show later what was done.
struct CompletionSheet: View {
    @Bindable var model: AppModel
    let routine: Routine
    let cycle: RoutineCycle
    let ring: RoutineCycle.StepRing
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var photo: Data?
    @State private var removePhoto = false
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var storedPhoto: Data?
    @State private var photoError: String?

    private var done: RoutineCompletion? { model.completion(routine, ring) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Rings", value: ring.at.formatted(date: .abbreviated, time: .shortened))
                    if let done {
                        LabeledContent(
                            "Done", value: done.completedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Note") {
                    TextField("What you did, such as the medication and dose", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("completion-note")
                }
                Section {
                    if let shown = photo ?? (removePhoto ? nil : storedPhoto), let image = UIImage(data: shown) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .accessibilityLabel("Photo")
                            .accessibilityIdentifier("completion-photo")
                        Button("Remove Photo", role: .destructive) {
                            photo = nil
                            removePhoto = true
                        }
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            camera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        .accessibilityIdentifier("take-photo")
                    }
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("choose-photo")
                    if let photoError {
                        Text(photoError).foregroundStyle(.red)
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("abera.tech keeps check-offs, notes and photos for two weeks, then deletes them.")
                }
                if done != nil {
                    Section {
                        Button("Undo Check-off", role: .destructive) {
                            Task { await model.undoStep(routine, cycle: cycle, step: ring.step) }
                            dismiss()
                        }
                        .accessibilityIdentifier("undo-completion")
                    }
                }
            }
            .navigationTitle(ring.step.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(done == nil ? "Done" : "Save") {
                        let note = note
                        let photo = photo
                        let removePhoto = removePhoto
                        Task {
                            await model.completeStep(
                                routine, cycle: cycle, step: ring.step, note: note, photo: photo,
                                removePhoto: removePhoto && photo == nil)
                        }
                        dismiss()
                    }
                    .disabled(note.count > CompletionDraft.maxNoteLength)
                    .accessibilityIdentifier("save-completion")
                }
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    use(data.flatMap(UIImage.init(data:)))
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in use(image) }
                    .ignoresSafeArea()
            }
            .task {
                // The status carries the note and whether a photo is kept, offline too.
                guard let done else { return }
                if note.isEmpty { note = done.note ?? "" }
                if done.hasPhoto, let id = done.id { storedPhoto = await model.photo(id) }
            }
        }
    }

    private func use(_ image: UIImage?) {
        guard let image, let jpeg = ProofPhoto.jpeg(image) else {
            photoError = "That photo could not be read."
            return
        }
        photoError = nil
        photo = jpeg
        removePhoto = false
    }
}

/// A photo sized for proof: at most 1600 pixels on its long side, JPEG,
/// under abera.tech's 2 MB cap.
enum ProofPhoto {
    static let longSide: CGFloat = 1600

    static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, longSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.7, 0.5, 0.3] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= CompletionDraft.maxPhotoBytes {
                return data
            }
        }
        return nil
    }
}

/// The camera, for a photo taken on the spot.
struct CameraPicker: UIViewControllerRepresentable {
    let taken: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.taken(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Two weeks of steps, newest first, for the weekend's check: how often
/// each step was done, then each day with what was done and what was missed.
struct HistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var history: RoutineHistory?
    @State private var error: String?
    @State private var shown: ShownPhoto?

    struct ShownPhoto: Identifiable {
        var id: UUID
        var title: String
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("history-error")
                }
                if let history {
                    if history.cycles.isEmpty {
                        Text("No steps in the last two weeks. Add steps to an alarm in its editor.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("history-empty")
                    } else {
                        Section("Last \(history.days) days") {
                            ForEach(history.tally(now: Date())) { row in
                                LabeledContent(row.label, value: "\(row.done) of \(row.of)")
                                    .accessibilityIdentifier("tally-\(row.label)")
                            }
                        }
                        ForEach(history.cycles) { cycle in
                            Section {
                                ForEach(cycle.steps) { step in
                                    HistoryStepRow(model: model, cycle: cycle, step: step) { id in
                                        shown = ShownPhoto(id: id, title: step.label)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(
                                        "\(cycle.label), \(StepText.when(cycle.at))"
                                            + (cycle.outcome?.status == .done ? ", done" : ""))
                                    Spacer()
                                    Text(cycle.doneText(now: Date()))
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("history-\(cycle.label)-\(cycle.cycle)")
                            }
                        }
                    }
                } else if error == nil {
                    ProgressView()
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $shown) { photo in
                PhotoView(model: model, id: photo.id, title: photo.title)
            }
        }
    }

    private func load() async {
        switch await model.history() {
        case .success(let read):
            history = read
            error = nil
        case .failure(let failure):
            error =
                failure == .offline
                ? "No connection to abera.tech. History needs one." : AppModel.describe(failure)
        }
    }
}

struct HistoryStepRow: View {
    @Bindable var model: AppModel
    let cycle: RoutineHistory.Cycle
    let step: RoutineHistory.Step
    let showPhoto: (UUID) -> Void

    /// Done, skipped with its alarm, still to ring, or missed.
    private var icon: String {
        if step.completion != nil { return "checkmark.circle.fill" }
        if cycle.skipped { return "forward.circle" }
        return step.at > Date() ? "circle" : "xmark.circle"
    }

    private var color: Color {
        if step.completion != nil { return .green }
        if cycle.skipped || step.at > Date() { return .secondary }
        return .red
    }

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                if let done = step.completion {
                    Text("Done \(StepText.on(done.completedAt, now: Date()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = done.note {
                        Text(note).font(.caption)
                    }
                } else if step.at > Date() {
                    Text("Rings \(StepText.on(step.at, now: Date()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        cycle.skipped
                            ? "Skipped with its alarm."
                            : "Missed. It rang at \(step.at.formatted(date: .omitted, time: .shortened))."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("history-step-\(step.label)-\(cycle.cycle)")
            Spacer()
            if let done = step.completion, done.hasPhoto {
                Button {
                    showPhoto(done.id)
                } label: {
                    Image(systemName: "photo")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Photo of \(step.label)")
                .accessibilityIdentifier("history-photo-\(step.label)-\(cycle.cycle)")
            }
        }
    }
}

struct PhotoView: View {
    @Bindable var model: AppModel
    let id: UUID
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Photo of \(title)")
                        .accessibilityIdentifier("history-photo-full")
                } else if failed {
                    Text("The photo could not be loaded.").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let data = await model.photo(id), let read = UIImage(data: data) {
                    image = read
                } else {
                    failed = true
                }
            }
        }
    }
}

/// Opens and closes an alarm's steps in one tap, and says how many of the
/// ring's steps are done. Open by default when the ring is today.
struct StepsToggleRow: View {
    @Bindable var model: AppModel
    let routine: Routine
    let open: Bool

    var body: some View {
        let cycle = model.shownCycle(routine, at: Date())
        let done = cycle?.steps.filter { model.completion(routine, $0) != nil }.count ?? 0
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.toggleSteps(routine, at: Date()) }
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(.secondary)
                Text(open ? "Hide steps" : "Show \(routine.steps.count) steps")
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                Spacer()
                Text("\(done) of \(routine.steps.count) done")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(done == routine.steps.count ? Color.green : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .accessibilityValue(open ? "Open" : "Closed")
        .accessibilityIdentifier("steps-toggle-\(routine.label)")
    }
}
