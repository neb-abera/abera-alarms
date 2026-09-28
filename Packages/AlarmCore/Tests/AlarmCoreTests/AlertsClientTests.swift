import Foundation
import Testing

@testable import AlarmCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A transport that answers one fixed status and body, and records the request.
actor ScriptedTransport: HTTPTransport {
    let status: Int
    let body: Data
    let failure: (any Error)?
    private(set) var last: URLRequest?

    init(status: Int = 200, body: Data = Data(), failure: (any Error)? = nil) {
        self.status = status
        self.body = body
        self.failure = failure
    }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        last = request
        if let failure { throw failure }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct AlertsClientTests {
    let okBody = Data(#"{"configured":true,"alerts":[]}"#.utf8)

    @Test func sendsTheTokenAndNothingElseSecret() async throws {
        let transport = ScriptedTransport(body: okBody)
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport).status()
        let request = try #require(await transport.last)
        #expect(request.url?.absoluteString == "https://abera.tech/api/alerts/status")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixtures.token)")
        #expect(request.httpBody == nil)
        #expect(request.url?.query == nil)
    }

    @Test func acknowledgesInTheBodyNeverTheAddress() async throws {
        let transport = ScriptedTransport(body: okBody)
        _ = try await AlertsClient(pairing: Fixtures.pairing, transport: transport).acknowledge(key: "uid|2026")
        let request = try #require(await transport.last)
        #expect(request.url?.path == "/api/alerts/ack")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["key": "uid|2026", "via": "phone"])
    }

    @Test(arguments: [
        (401, APIError.unpaired), (403, APIError.status(403)), (404, APIError.notFound),
        (429, APIError.rateLimited), (500, APIError.status(500)), (502, APIError.status(502)),
    ])
    func mapsTheStatus(status: Int, expected: APIError) async {
        let client = AlertsClient(pairing: Fixtures.pairing, transport: ScriptedTransport(status: status))
        await #expect(throws: expected) { try await client.status() }
    }

    @Test func refusesAnAnswerThatIsNotTheState() async {
        let client = AlertsClient(pairing: Fixtures.pairing, transport: ScriptedTransport(body: Data("<html>".utf8)))
        await #expect(throws: APIError.badResponse) { try await client.status() }
    }

    @Test func refusesAnOversizedAnswer() async {
        let huge = Data(count: AlertsClient.maxResponseBytes + 1)
        let client = AlertsClient(pairing: Fixtures.pairing, transport: ScriptedTransport(body: huge))
        await #expect(throws: APIError.badResponse) { try await client.status() }
    }

    @Test func callsANetworkFailureOffline() async {
        let client = AlertsClient(
            pairing: Fixtures.pairing, transport: ScriptedTransport(failure: URLError(.timedOut)))
        await #expect(throws: APIError.offline) { try await client.status() }
    }
}
