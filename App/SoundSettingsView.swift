import AVFoundation
import AlarmCore
import SwiftUI

/// The sound every alarm plays and how long Snooze waits on a calendar
/// alarm. Saved on abera.tech, so the page shows the same choice.
struct SoundSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sound: String
    @State private var snoozeMinutes: Int
    @State private var player: AVAudioPlayer?

    init(model: AppModel) {
        self.model = model
        _sound = State(initialValue: model.phone.sound)
        _snoozeMinutes = State(initialValue: model.phone.snoozeMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Alarm sound", selection: $sound) {
                        ForEach(PhoneSettings.sounds, id: \.value) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("sound-picker")
                    .onChange(of: sound) { _, name in preview(name) }
                } header: {
                    Text("Alarm sound")
                } footer: {
                    Text("Every alarm plays it: the Alarms tab and calendar events set to Ring until stopped.")
                }
                Section {
                    Stepper("Snooze: \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...30)
                        .accessibilityIdentifier("snooze-stepper")
                } footer: {
                    Text("For calendar alarms. Each alarm on the Alarms tab keeps its own snooze.")
                }
                if let error = model.settingsError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Sound & Snooze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.savePhoneSettings(PhoneSettings(sound: sound, snoozeMinutes: snoozeMinutes))
                            if model.settingsError == nil { dismiss() }
                        }
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("save-sound")
                }
            }
            .onDisappear { player?.stop() }
        }
    }

    /// Plays two seconds of the chosen sound. The iPhone default has no
    /// file to play here.
    private func preview(_ name: String) {
        player?.stop()
        guard name != "default", let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [player] in player?.stop() }
    }
}
