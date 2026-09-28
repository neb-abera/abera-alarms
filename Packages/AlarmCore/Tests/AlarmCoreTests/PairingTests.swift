import Foundation
import Testing

@testable import AlarmCore

@Suite struct PairingTests {
    let token = Fixtures.token

    @Test func readsTheLinkThePageShows() throws {
        let pairing = try PairingLink.parse("aberaalarms://pair#token=\(token)&server=https%3A%2F%2Fabera.tech")
        #expect(pairing == Pairing(server: URL(string: "https://abera.tech")!, token: token))
    }

    @Test func defaultsToAberaTech() throws {
        let pairing = try PairingLink.parse("  aberaalarms://pair#token=\(token)\n")
        #expect(pairing.server == Pairing.production)
    }

    @Test func normalizesTheServer() throws {
        let pairing = try PairingLink.parse("aberaalarms://pair#token=\(token)&server=HTTPS://Abera.Tech/alerts/")
        #expect(pairing.server == Pairing.production)
    }

    @Test(arguments: [
        "https://abera.tech/alerts",
        "aberaalarms://unpair#token=TOKEN",
        "otherapp://pair#token=TOKEN",
        "aberaalarms://pair?token=TOKEN",
        "not a link",
    ])
    func refusesWhatIsNotAPairingLink(link: String) {
        #expect(throws: PairingError.notAPairingLink) {
            try PairingLink.parse(link.replacingOccurrences(of: "TOKEN", with: token))
        }
    }

    @Test(arguments: [
        "aberaalarms://pair#token=",
        "aberaalarms://pair#token=aat_short",
        "aberaalarms://pair#token=xyz_" + String(repeating: "A", count: 43),
        "aberaalarms://pair#token=aat_" + String(repeating: "A", count: 42) + "%2B",
        "aberaalarms://pair#server=https%3A%2F%2Fabera.tech",
    ])
    func refusesABadToken(link: String) {
        #expect(throws: PairingError.badToken) { try PairingLink.parse(link) }
    }

    @Test(arguments: [
        "https%3A%2F%2Fevil.example",
        "http%3A%2F%2Fabera.tech",
        "https%3A%2F%2Fuser%3Apass%40abera.tech",
        "javascript%3Aalert(1)",
    ])
    func refusesAServerThisBuildDoesNotAllow(server: String) {
        #expect(throws: PairingError.serverNotAllowed) {
            try PairingLink.parse("aberaalarms://pair#token=\(token)&server=\(server)")
        }
    }

    @Test func allowsLoopbackOnlyWhenTheBuildDoes() throws {
        let link = "aberaalarms://pair#token=\(token)&server=http%3A%2F%2Flocalhost%3A8080"
        #expect(throws: PairingError.serverNotAllowed) { try PairingLink.parse(link) }
        let local = URL(string: "http://localhost:8080")!
        #expect(try PairingLink.parse(link, allowedServers: [local]).server == local)
    }

    @Test func refusesALinkLongerThanAPairingLink() {
        let link = "aberaalarms://pair#token=\(token)&pad=" + String(repeating: "x", count: 600)
        #expect(throws: PairingError.notAPairingLink) { try PairingLink.parse(link) }
    }
}
