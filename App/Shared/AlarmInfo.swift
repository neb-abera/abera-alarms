import AlarmKit

/// What an alarm carries: the calendar occurrence key, or "routine:" and
/// the routine's id. Shared with the widget extension, which draws the
/// snooze countdown.
struct AlarmInfo: AlarmMetadata {
    var key: String
}
