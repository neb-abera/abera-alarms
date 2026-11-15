import AlarmCore
import Foundation

/// The widgets' snapshot in the app group, which the app and the widget
/// share. The app writes it. The widget only reads it.
enum WidgetStore {
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appending(path: WidgetSnapshot.fileName, directoryHint: .notDirectory)
    }

    /// Nil before the app first wrote one, or when the group is missing.
    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    /// Readable after the first unlock, as the Lock Screen widgets draw
    /// while the phone is locked. False when nothing was written.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url, let data = try? snapshot.encoded() else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
            != nil
    }
}
