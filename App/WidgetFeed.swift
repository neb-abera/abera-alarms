import AlarmCore
import Foundation
import WidgetKit

/// Writes what the widgets show after every sync and every change on the
/// phone: the alarms the alarm system holds, the running timer, the next
/// events and the countdowns. The widgets reload only when it changed.
enum WidgetFeed {
    static func publish(_ dependencies: Dependencies = .shared) async {
        let paired = await dependencies.sync.pairing() != nil
        let state = paired ? await dependencies.sync.lastState() : nil
        let held = paired ? await dependencies.sync.heldAlarms() : []
        var timer: WidgetSnapshot.OneTime?
        if let endsAt = await dependencies.device.timerEndsAt() {
            timer = WidgetSnapshot.OneTime(title: await dependencies.device.timerLabel(), at: endsAt)
        }
        let snapshot = WidgetSnapshot.make(state: state, held: held, timer: timer, paired: paired, now: Date())
        if var old = WidgetStore.read() {
            old.writtenAt = snapshot.writtenAt
            if old == snapshot { return }
        }
        guard WidgetStore.write(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
