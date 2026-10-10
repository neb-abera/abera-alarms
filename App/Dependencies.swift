import AlarmCore
import Foundation
import Security

enum AlarmPermission: Sendable {
    case allowed
    case denied
    case notAsked
}

protocol AlarmPermissions: Sendable {
    func current() async -> AlarmPermission
    func request() async -> AlarmPermission
}

/// The one set of parts the app, the background refresh and the Stop
/// button share.
struct Dependencies: Sendable {
    let sync: AlarmSync
    let permissions: any AlarmPermissions
    let allowedServers: Set<URL>

    static let shared: Dependencies = {
        #if DEBUG
            if let demo = Demo.fromLaunchArguments() { return demo }
        #endif
        return Dependencies(
            sync: AlarmSync(
                credentials: KeychainCredentials(),
                transport: URLSession(configuration: .ephemeral),
                alarms: AlarmKitScheduler(),
                documents: FileDocuments(),
                uploads: AcknowledgementUploads.shared),
            permissions: AlarmKitPermissions(),
            allowedServers: [Pairing.production])
    }()
}

/// The pairing, in the Keychain, readable after the first unlock so the
/// Stop button and the background refresh work on a locked phone, and never
/// copied to a backup or another device.
struct KeychainCredentials: CredentialStore {
    struct KeychainError: Error {
        let status: OSStatus
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.abera.alarms",
            kSecAttrAccount as String: "pairing",
        ]
    }

    func load() async throws -> Pairing? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Pairing.self, from: data)
    }

    func save(_ pairing: Pairing) async throws {
        try await remove()
        var item = query()
        item[kSecValueData as String] = try JSONEncoder().encode(pairing)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func remove() async throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// The ledger, the waiting acknowledgements and the last state, in
/// Application Support. Readable after the first unlock, like the token.
struct FileDocuments: DocumentStore {
    private func url(_ name: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "AberaAlarms", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    func load(_ name: String) async throws -> Data? {
        let file = try url(name)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        return try Data(contentsOf: file)
    }

    func save(_ data: Data, as name: String) async throws {
        try data.write(to: try url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ name: String) async throws {
        let file = try url(name)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

/// Stop's acknowledgement in a background URLSession. iOS sends it after the
/// app is suspended or ended, retries it, and wakes the app with the result.
/// On 2026-10-10 a Stop's one foreground request never reached abera.tech
/// and Pushover rang 10 minutes later.
struct AcknowledgementUploads: BackgroundUploading {
    static let identifier = "tech.abera.alarms.acknowledgements"
    static let shared = AcknowledgementUploads()

    /// Set by the app delegate when iOS wakes the app for this session, and
    /// called once its events are delivered.
    @MainActor static var finishEvents: (() -> Void)?

    let session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // iOS retries until this runs out. A day later no ring is left to stop.
        configuration.timeoutIntervalForResource = 24 * 3600
        return URLSession(configuration: configuration, delegate: AcknowledgementEvents(), delegateQueue: nil)
    }()

    /// A background session uploads from a file, so the body is written to
    /// one, readable on a locked phone as the ledger is.
    static func directory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "AberaAlarms/uploads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func upload(_ request: URLRequest, label: String) async throws {
        let name = UUID().uuidString
        let file = try Self.directory().appending(path: name, directoryHint: .notDirectory)
        try (request.httpBody ?? Data()).write(
            to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var request = request
        request.httpBody = nil
        let task = session.uploadTask(with: request, fromFile: file)
        // The file and the key, for the result after a relaunch.
        task.taskDescription = "\(name) \(label)"
        task.resume()
    }
}

final class AcknowledgementEvents: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let parts = task.taskDescription?.split(separator: " ", maxSplits: 1) ?? []
        guard parts.count == 2 else { return }
        if let directory = try? AcknowledgementUploads.directory() {
            try? FileManager.default.removeItem(at: directory.appending(path: String(parts[0])))
        }
        let status = error == nil ? (task.response as? HTTPURLResponse)?.statusCode : nil
        let key = String(parts[1])
        // A key this misses stays waiting, and the next sync sends it again.
        Task { await Dependencies.shared.sync.uploadFinished(label: key, status: status) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            AcknowledgementUploads.finishEvents?()
            AcknowledgementUploads.finishEvents = nil
        }
    }
}
