import Foundation

/// The phone's credential for abera.tech: the server and the device token
/// the owner created on /alerts.
public struct Pairing: Codable, Equatable, Sendable {
    public var server: URL
    public var token: String

    public init(server: URL, token: String) {
        self.server = server
        self.token = token
    }

    /// The one server a release build pairs with.
    public static let production = URL(string: "https://abera.tech")!

    /// `aat_` and 43 base64url characters: 32 random bytes from the server.
    public static func isToken(_ text: String) -> Bool {
        guard text.hasPrefix("aat_"), text.utf8.count == 47 else { return false }
        return text.utf8.dropFirst(4).allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D || byte == 0x5F
        }
    }
}

public enum PairingError: Error, Equatable, Sendable {
    case notAPairingLink
    case badToken
    case serverNotAllowed
}

/// The link /alerts shows when a phone is paired:
/// `aberaalarms://pair#token=aat_…&server=https%3A%2F%2Fabera.tech`.
///
/// The token rides in the fragment, which no web server is ever sent. The
/// server must be one this build allows, so a link from anyone else cannot
/// point the app at a server that would feed it alarms.
public enum PairingLink {
    public static let scheme = "aberaalarms"

    public static func parse(_ text: String, allowedServers: Set<URL> = [Pairing.production]) throws(PairingError)
        -> Pairing
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 512,
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == scheme,
            components.host?.lowercased() == "pair",
            let fragment = components.fragment
        else { throw .notAPairingLink }

        var fields = URLComponents()
        fields.percentEncodedQuery = fragment
        let items = fields.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let token = value("token"), Pairing.isToken(token) else { throw .badToken }

        let server = value("server").flatMap(URL.init(string:)) ?? Pairing.production
        guard let normalized = normalize(server), allowedServers.contains(normalized) else { throw .serverNotAllowed }
        return Pairing(server: normalized, token: token)
    }

    /// Scheme and host in lower case, no path, no trailing slash. Only
    /// https, except a loopback address for a development server.
    static func normalize(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(), !host.isEmpty,
            components.user == nil, components.password == nil
        else { return nil }
        let loopback = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && loopback) else { return nil }
        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
