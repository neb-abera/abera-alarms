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
                documents: FileDocuments()),
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
