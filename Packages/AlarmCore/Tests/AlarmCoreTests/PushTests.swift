import Foundation
import Testing

@testable import AlarmCore

/// The phone tells abera.tech where to push, and stops it on Unpair.
@Suite struct PushTests {
    let token = String(repeating: "ab", count: 32)

    @Test func tokensAreLowercaseHex() {
        #expect(PushToken.hex(Data([0x00, 0xAB, 0x10, 0xFF])) == "00ab10ff")
        #expect(PushToken.isValid(token))
        #expect(!PushToken.isValid(String(repeating: "AB", count: 32)))
        #expect(!PushToken.isValid("abc"))
        #expect(!PushToken.isValid(String(repeating: "g", count: 64)))
        #expect(!PushToken.isValid(String(repeating: "a", count: 202)))
    }

    @Test func registeringStoresTheTokenAndEnvironment() async {
        let rig = Fixtures.rig([])
        #expect(await rig.sync.registerPush(token: token, environment: .sandbox) == nil)
        #expect(await rig.server.pushRegistration == "\(token) sandbox")
        #expect(await rig.server.requests == ["PUT /api/alerts/devices/me/push"])
    }

    @Test func anUnpairedPhoneRegistersNothing() async {
        let rig = Fixtures.rig([], paired: false)
        #expect(await rig.sync.registerPush(token: token, environment: .production) == .unpaired)
        #expect(await rig.server.requests.isEmpty)
    }

    @Test func aBadTokenIsNotSent() async {
        let rig = Fixtures.rig([])
        #expect(await rig.sync.registerPush(token: "zz", environment: .sandbox) == .badResponse)
        #expect(await rig.server.requests.isEmpty)
    }

    @Test func offlineRegistrationSaysSo() async {
        let rig = Fixtures.rig([])
        await rig.server.setOffline(true)
        #expect(await rig.sync.registerPush(token: token, environment: .sandbox) == .offline)
    }

    @Test func unpairingStopsThePushes() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.registerPush(token: token, environment: .sandbox)
        await rig.sync.unpair()
        #expect(await rig.server.pushRegistration == nil)
        #expect(await rig.credentials.load() == nil)
    }

    @Test func unpairingOfflineStillUnpairs() async {
        let rig = Fixtures.rig([Fixtures.alert("a", inMinutes: 30)])
        _ = await rig.sync.sync()
        await rig.server.setOffline(true)
        await rig.sync.unpair()
        #expect(await rig.credentials.load() == nil)
        #expect(await rig.alarms.alarms.isEmpty)
    }

    @Test func registrationSendsHexAndEnvironmentInTheBody() async throws {
        let transport = ScriptedTransport(status: 204)
        try await AlertsClient(pairing: Fixtures.pairing, transport: transport)
            .registerPush(token: token, environment: .production)
        let request = try #require(await transport.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/alerts/devices/me/push")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["apnsToken": token, "environment": "production"])
    }
}
