import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One weigh-in as Apple Health holds it.
public struct WeightSample: Equatable, Sendable {
    public let date: Date
    public let kilograms: Double

    public init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}

/// One day's weigh-in, as abera.tech keeps them: the day in the phone's zone.
public struct DailyWeight: Codable, Equatable, Sendable {
    public let date: String
    public let weightKg: Double

    public init(date: String, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

/// What abera.tech did with an upload.
public struct WeightUploadResult: Codable, Equatable, Sendable {
    public let saved: Int
    public let unchanged: Int
}

/// The phone's weigh-ins. The app passes Apple Health. Tests pass a fake.
public protocol WeightReading: Sendable {
    /// Weigh-ins since the date, in any order.
    func samples(since: Date) async throws -> [WeightSample]
}

extension AlertsClient {
    /// The weigh-ins of recent days, for abera.tech/fitness.
    public func uploadWeights(_ weights: [DailyWeight]) async throws(APIError) -> WeightUploadResult {
        let data = try await send("POST", "health/weights", body: WeightsBody(weights: weights))
        guard let result = try? JSONDecoder().decode(WeightUploadResult.self, from: data) else { throw .badResponse }
        return result
    }
}

private struct WeightsBody: Encodable, Sendable {
    let weights: [DailyWeight]
}

/// Sends Apple Health's weigh-ins to abera.tech/fitness.
///
/// Neb logs his weight in Lose It, which writes it to Apple Health and
/// sends nothing to Garmin. Apple Health has no server API, so the phone
/// reads it and sends it (2026-11-21).
///
/// Each run sends the last 30 days, one weigh-in a day: the last of the
/// day, as the scale or the log ended it. abera.tech stores a day once and
/// answers a repeat with nothing changed. A run that would send exactly
/// what the last one sent stops before the network.
public actor WeightSync {
    public static let days = 30
    static let sentDocument = "weights-sent.json"

    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let reader: any WeightReading
    let documents: any DocumentStore
    let now: @Sendable () -> Date
    let calendar: Calendar

    public init(
        credentials: any CredentialStore,
        transport: any HTTPTransport,
        reader: any WeightReading,
        documents: any DocumentStore,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.credentials = credentials
        self.transport = transport
        self.reader = reader
        self.documents = documents
        self.now = now
        self.calendar = calendar
    }

    public enum Outcome: Equatable, Sendable {
        case notPaired
        /// Apple Health gave nothing: no weigh-ins, or no permission. iOS
        /// does not tell an app which.
        case nothingToSend
        /// The same days and weights as the last run.
        case alreadySent
        case sent(WeightUploadResult)
        case failed(APIError)
    }

    @discardableResult
    public func run() async -> Outcome {
        guard let pairing = try? await credentials.load() else { return .notPaired }
        let since = calendar.date(byAdding: .day, value: -Self.days, to: calendar.startOfDay(for: now())) ?? now()
        guard let samples = try? await reader.samples(since: since) else { return .nothingToSend }
        let weights = Self.daily(samples, calendar: calendar)
        guard !weights.isEmpty else { return .nothingToSend }

        // Sorted keys: the encoder's key order is not fixed, and this is compared byte for byte.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try? encoder.encode(weights)
        if let body, let last = try? await documents.load(Self.sentDocument), last == body { return .alreadySent }

        do {
            let result = try await AlertsClient(pairing: pairing, transport: transport).uploadWeights(weights)
            if let body { try? await documents.save(body, as: Self.sentDocument) }
            return .sent(result)
        } catch {
            return .failed(error)
        }
    }

    /// One weigh-in a day, the last of the day in the calendar's zone, oldest
    /// first. A sample abera.tech would refuse is left out, so one bad
    /// reading does not stop the rest.
    static func daily(_ samples: [WeightSample], calendar: Calendar) -> [DailyWeight] {
        var last: [String: WeightSample] = [:]
        for sample in samples where sample.kilograms > 30 && sample.kilograms <= 250 {
            let day = dayString(sample.date, calendar: calendar)
            if let held = last[day], held.date >= sample.date { continue }
            last[day] = sample
        }
        return last.keys.sorted().map { DailyWeight(date: $0, weightKg: (last[$0]!.kilograms * 1000).rounded() / 1000) }
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
