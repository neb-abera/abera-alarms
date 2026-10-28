import AVFoundation
import AlarmCore
import SwiftUI
import UIKit

/// The Timer tab: the workout clock, the set it is timing, Next set, and
/// the sets done. Every interval the phone says the time on the clock.
struct WorkoutView: View {
    @Bindable var timer: WorkoutModel
    var onScreen = true
    @State private var confirmingReset = false

    private var workout: Workout { timer.workout }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("Set \(workout.set)")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("workout-set")
                    // Four ticks a second while it runs on screen, so the
                    // seconds turn over on time. Otherwise it waits a day.
                    TimelineView(.periodic(from: .now, by: onScreen && workout.running ? 0.25 : 86_400)) { context in
                        VStack(spacing: 4) {
                            Text(Workout.clock(workout.elapsed(at: context.date)))
                                .font(.system(size: 80, weight: .light).monospacedDigit())
                                .accessibilityIdentifier("workout-clock")
                            if !workout.sets.isEmpty {
                                Text("Total \(Workout.clock(workout.total(at: context.date)))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("workout-total")
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        Button {
                            timer.startOrPause()
                        } label: {
                            Text(workout.running ? "Pause" : workout.started ? "Resume" : "Start")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(workout.running ? .orange : .green)
                        .accessibilityIdentifier("workout-start")
                        Button {
                            timer.nextSet()
                        } label: {
                            Text("Next set")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!workout.started)
                        .accessibilityIdentifier("workout-next-set")
                    }
                    .padding(.horizontal)
                    Button(role: .destructive) {
                        timer.stop()
                    } label: {
                        Text("Stop")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!workout.started)
                    .padding(.horizontal)
                    .accessibilityIdentifier("workout-stop")
                }
                .padding(.vertical)
                List {
                    Section {
                        Picker("Say the time every", selection: $timer.interval) {
                            ForEach(Workout.intervals, id: \.self) { seconds in
                                Text(Workout.intervalText(seconds)).tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("workout-interval")
                    } footer: {
                        Text(
                            workout.interval == 0
                                ? "The timer is silent."
                                : "A voice says the time on the clock, over music and with the phone locked. Next set says the set's number. Stop ends the set and the voice."
                        )
                    }
                    if !workout.sets.isEmpty {
                        Section("Sets done") {
                            ForEach(Array(workout.sets.enumerated()).reversed(), id: \.offset) { index, time in
                                LabeledContent("Set \(index + 1)", value: Workout.clock(time))
                                    .monospacedDigit()
                                    .accessibilityIdentifier("workout-done-\(index + 1)")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset Session") { confirmingReset = true }
                        .disabled(!workout.started && workout.sets.isEmpty)
                        .accessibilityIdentifier("workout-reset-session")
                }
            }
            .confirmationDialog("Reset the session?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset Session", role: .destructive) { timer.resetSession() }
                    .accessibilityIdentifier("confirm-reset-session")
            } message: {
                Text("Back to set 1 at 0:00. The list of sets done is cleared.")
            }
        }
    }
}

/// The workout timer's state, kept on the phone so it survives the app
/// being closed, and the voice that says the times.
@MainActor
@Observable
final class WorkoutModel {
    static let key = "workout"

    private(set) var workout: Workout
    @ObservationIgnored private let store: UserDefaults?
    @ObservationIgnored private let voice = WorkoutVoice()
    @ObservationIgnored private var marks: Task<Void, Never>?

    /// No store in -demo mode, so every UI test starts at set 1.
    init(store: UserDefaults? = ProcessInfo.processInfo.arguments.contains("-demo") ? nil : .standard) {
        self.store = store
        workout =
            store?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Workout.self, from: $0) } ?? Workout()
        follow()
    }

    var interval: Int {
        get { workout.interval }
        set {
            workout.interval = newValue
            changed()
        }
    }

    func startOrPause() {
        if workout.running { workout.pause(at: Date()) } else { workout.start(at: Date()) }
        changed()
    }

    func nextSet() {
        workout.nextSet(at: Date())
        changed()
        voice.say("Set \(workout.set)")
    }

    /// Done: the set is recorded, the clock reads 0:00, and the voice and
    /// its audio are off.
    func stop() {
        workout.stop(at: Date())
        changed()
    }

    func resetSession() {
        workout.resetSession()
        changed()
    }

    private func changed() {
        if let data = try? JSONEncoder().encode(workout) { store?.set(data, forKey: Self.key) }
        follow()
    }

    /// Says each mark while the clock runs and the interval is on. A mark
    /// more than 2 s late is skipped: the time it names has passed.
    private func follow() {
        marks?.cancel()
        marks = nil
        guard workout.running, workout.interval > 0 else {
            voice.end()
            return
        }
        voice.begin()
        let workout = workout
        let voice = voice
        marks = Task {
            var after = Date()
            while let mark = workout.nextAnnouncement(after: after) {
                try? await Task.sleep(for: .seconds(max(0, mark.at.timeIntervalSinceNow)))
                if Task.isCancelled { return }
                if Date().timeIntervalSince(mark.at) < 2 { voice.say(Workout.spoken(mark.seconds)) }
                after = max(mark.at, Date())
            }
        }
    }
}

/// Says the workout's times over music, in earbuds or on the speaker, with
/// the phone locked and the silent switch on. iOS keeps an app running in
/// the background only while it plays audio, so silence plays between the
/// times. Music is lowered while the voice speaks, and a podcast pauses.
@MainActor
final class WorkoutVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let silence = AVAudioPlayerNode()
    private let quiet: AVAudioPCMBuffer?
    private let voice = WorkoutVoice.bestVoice()
    private var on = false

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        quiet = format.flatMap { AVAudioPCMBuffer(pcmFormat: $0, frameCapacity: 44_100) }
        if let quiet, let samples = quiet.floatChannelData {
            quiet.frameLength = quiet.frameCapacity
            samples[0].update(repeating: 0, count: Int(quiet.frameLength))
        }
        super.init()
        synthesizer.delegate = self
        engine.attach(silence)
        engine.connect(silence, to: engine.mainMixerNode, format: format)
        // Both arrive on any thread. The main queue hands them to this actor.
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) {
            [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .ended else { return }
            MainActor.assumeIsolated { self?.resume() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
    }

    /// Starts the silence that keeps the app running. Music keeps playing.
    func begin() {
        guard !on else { return }
        on = true
        mix()
    }

    func end() {
        guard on else { return }
        on = false
        synthesizer.stopSpeaking(at: .immediate)
        silence.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func say(_ text: String) {
        guard on else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.unduck() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.unduck() }
    }

    /// Music comes back up once the voice is done. Ducking ends only when
    /// the session is switched off, so the silence stops for a moment.
    private func unduck() {
        guard on, !synthesizer.isSpeaking else { return }
        silence.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        mix()
    }

    private func mix() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers])
        try? session.setActive(true)
        restart()
    }

    /// Plays the silence again after a route change or a pause.
    private func restart() {
        guard on, let quiet else { return }
        silence.stop()
        do { try engine.start() } catch { return }
        silence.scheduleBuffer(quiet, at: nil, options: .loops)
        silence.play()
    }

    /// After a call or another app's audio ends.
    private func resume() {
        guard on else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        restart()
    }

    /// The best voice installed for the phone's language: premium, then
    /// enhanced, then the default. Novelty voices are left out.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }
}
