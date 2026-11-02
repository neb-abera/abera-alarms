import Foundation

/// When the workout voice lowers music and when it brings it back up.
/// Music comes back up only when the audio session is switched off, and
/// iOS refuses that while the speech audio is still winding down. So a
/// refused attempt is tried again, and a backstop brings music up when a
/// finished utterance was never reported.
public struct Ducking: Equatable, Sendable {
    /// Waits before each new attempt to bring music up, in seconds: quick
    /// at first, then once a second. After the last, the next time said
    /// tries again.
    public static let retryDelays: [TimeInterval] = [0.1, 0.2, 0.4, 0.8] + Array(repeating: 1, count: 26)
    /// Seconds after a time is said before music comes up whatever was
    /// reported. A spoken time takes under 3 s.
    public static let backstop: TimeInterval = 10

    /// Utterances asked for and not yet reported done.
    public private(set) var speaking = 0
    /// True while music is lowered.
    public private(set) var ducked = false

    public init() {}

    /// The voice is about to speak: music goes down.
    public mutating func willSpeak() {
        speaking += 1
        ducked = true
    }

    /// An utterance finished or was cancelled. True when music should come
    /// back up: lowered, and nothing left to say.
    public mutating func finished() -> Bool {
        speaking = max(0, speaking - 1)
        return ducked && speaking == 0
    }

    /// The backstop fired and the synthesizer says nothing. True when music
    /// is still lowered and should come up.
    public mutating func settle() -> Bool {
        guard ducked else { return false }
        speaking = 0
        return true
    }

    /// Music is back up.
    public mutating func restored() {
        ducked = false
    }

    /// The wait before attempt `attempt + 1`, after attempt `attempt`
    /// (from 0) was refused. Nil once every retry is spent.
    public static func retryDelay(after attempt: Int) -> TimeInterval? {
        retryDelays.indices.contains(attempt) ? retryDelays[attempt] : nil
    }
}
