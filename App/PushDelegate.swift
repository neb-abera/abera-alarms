import AlarmCore
import UIKit

/// Push notifications from abera.tech. A push carries no content: it wakes
/// the app, which syncs as it would on launch. iOS rations these pushes and
/// drops them for an app force-quit from the app switcher, so launch and
/// background refresh still sync too.
final class PushDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = PushToken.hex(deviceToken)
        Task {
            await PushRegistration.shared.received(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // The simulator on an Intel Mac, or no connection at launch. The
        // next launch asks again.
    }

    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let report = await Dependencies.shared.sync.sync()
        if report.error != nil { return .failed }
        return report.scheduled + report.cancelled > 0 ? .newData : .noData
    }
}

/// The latest device token, sent to abera.tech now if the phone is paired,
/// or again right after pairing.
actor PushRegistration {
    static let shared = PushRegistration()

    private var token: String?

    func received(_ token: String) async {
        self.token = token
        await send()
    }

    /// After a pairing, the token that arrived before it.
    func send() async {
        guard let token else { return }
        _ = await Dependencies.shared.sync.registerPush(token: token, environment: Self.environment)
    }

    /// Which APNs host this build's token belongs to. A build Xcode installs
    /// embeds a provisioning profile whose aps-environment is "development".
    /// TestFlight and App Store builds embed none and use production.
    static let environment: PushEnvironment = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else { return .production }
        let text = String(decoding: data, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>") else { return .production }
        let rest = text[key.upperBound...].prefix(80)
        return rest.contains("<string>development</string>") ? .sandbox : .production
    }()
}
