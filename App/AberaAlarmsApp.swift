import AlarmCore
import SwiftUI
import UIKit

@main
struct AberaAlarmsApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        #if DEBUG
            // The UI tests run in -demo mode. With animations on, iOS 27 never
            // reports a menu over the tab bar as settled, and every step
            // after it waits 60 s for the app to idle.
            if ProcessInfo.processInfo.arguments.contains("-demo") { UIView.setAnimationsEnabled(false) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL { url in
                    Task { await model.pair(link: url.absoluteString) }
                }
        }
        .onChange(of: phase) { _, now in
            guard now == .active, model.started, model.paired else { return }
            Task { await model.sync() }
        }
        .onChange(of: phase) { _, now in
            if now == .background { AppModel.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTask)) {
            await AppModel.backgroundRefresh()
        }
    }
}

/// The alarm's title on the lock screen: the event and its start, in the
/// phone's own zone.
enum AlarmText {
    static func title(for alarm: DesiredAlarm) -> String {
        "\(alarm.title), \(alarm.startsAt.formatted(date: .omitted, time: .shortened))"
    }
}
