import AlarmCore
import AppIntents
import SwiftUI
import WidgetKit

// The Home Screen and Lock Screen widgets. Each reads the snapshot the app
// writes into the app group (App/Shared/WidgetStore.swift) and never
// reaches abera.tech. A tap opens the app.

// MARK: Next alarm

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    /// Nil before the app wrote a snapshot.
    let snapshot: WidgetSnapshot?

    var ring: WidgetSnapshot.Ring? { snapshot?.nextRing(after: date) }
    var event: WidgetSnapshot.Event? { snapshot?.nextEvent(after: date, besides: ring) }
}

struct NextAlarmProvider: TimelineProvider {
    /// The widget gallery's sample, before any data.
    static let sample = WidgetSnapshot(
        writtenAt: .now, alarms: [.init(title: "Standup", at: .now.addingTimeInterval(3600))],
        events: [.init(title: "Lunch", startsAt: .now.addingTimeInterval(3 * 3600))])

    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(NextAlarmEntry(date: .now, snapshot: WidgetStore.read() ?? (context.isPreview ? Self.sample : nil)))
    }

    /// An entry now and one at each ring in the next 6 hours, so the widget
    /// moves to the next alarm as each one rings, with no help from the
    /// app. WidgetKit asks again after 6 hours, or sooner when the app writes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.read()
        let end = now.addingTimeInterval(6 * 3600)
        let times = [now] + (snapshot?.rings(after: now, through: end, limit: 60).map(\.at) ?? [])
        let entries = times.map { NextAlarmEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(end)))
    }
}

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tech.abera.alarms.next-alarm", provider: NextAlarmProvider()) { entry in
            NextAlarmView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next alarm")
        .description("The next alarm that rings on this phone, and the time to it.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

enum WidgetText {
    /// "09:30", or "Tue 09:30" when it is not today.
    static func time(_ date: Date, from now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return time }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    static func icon(_ kind: WidgetSnapshot.Ring.Kind) -> String {
        switch kind {
        case .calendar: "calendar"
        case .routine: "alarm"
        case .timer: "timer"
        }
    }

    static let empty = "No alarm set"
    static let unread = "Open Alarms to load your alarms"
}

/// Counts down to the ring once a second within a day, and in words past it.
struct RingCountdown: View {
    let ring: WidgetSnapshot.Ring
    let now: Date

    var body: some View {
        if ring.at.timeIntervalSince(now) < 86_400 {
            Text(ring.at, style: .timer)
        } else {
            Text(ring.at, style: .relative)
        }
    }
}

struct NextAlarmView: View {
    let entry: NextAlarmEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: home
        }
    }

    private var emptyText: String { entry.snapshot == nil ? WidgetText.unread : WidgetText.empty }

    @ViewBuilder private var inline: some View {
        if let ring = entry.ring {
            Label("\(ring.title) \(WidgetText.time(ring.at, from: entry.date))", systemImage: "alarm")
        } else {
            Label(WidgetText.empty, systemImage: "alarm")
        }
    }

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "alarm")
                if let ring = entry.ring {
                    Text(ring.at.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .minimumScaleFactor(0.5)
                } else {
                    Text("None")
                        .font(.caption2)
                }
            }
        }
        .accessibilityLabel(entry.ring.map { "Next alarm \($0.title)" } ?? WidgetText.empty)
    }

    @ViewBuilder private var rectangular: some View {
        if let ring = entry.ring {
            VStack(alignment: .leading) {
                Label(ring.title, systemImage: WidgetText.icon(ring.kind))
                    .font(.headline)
                    .widgetAccentable()
                Text(WidgetText.time(ring.at, from: entry.date))
                RingCountdown(ring: ring, now: entry.date)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(emptyText, systemImage: "alarm")
        }
    }

    @ViewBuilder private var home: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ring = entry.ring {
                Label("Next alarm", systemImage: WidgetText.icon(ring.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ring.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("widget-next-alarm-title")
                Text(WidgetText.time(ring.at, from: entry.date))
                    .font(.subheadline)
                RingCountdown(ring: ring, now: entry.date)
                    .font(.title2.monospacedDigit())
                if family == .systemMedium, let event = entry.event {
                    Spacer(minLength: 0)
                    Text("Next event: \(event.title), \(WidgetText.time(event.startsAt, from: entry.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Label("Next alarm", systemImage: "alarm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(emptyText)
                    .font(.headline)
                if family == .systemMedium, let event = entry.event {
                    Text("Next event: \(event.title), \(WidgetText.time(event.startsAt, from: entry.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Countdown

/// A countdown on abera.tech, as the widget's configuration offers it.
struct CountdownEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static let defaultQuery = CountdownQuery()

    let id: UUID
    let label: String
    let target: String

    init(_ countdown: Countdown) {
        id = countdown.id
        label = countdown.label
        target = countdown.targetText(at: .now)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(target)")
    }
}

struct CountdownQuery: EntityQuery {
    private var countdowns: [Countdown] { WidgetStore.read()?.countdowns ?? [] }

    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        countdowns.filter { identifiers.contains($0.id) }.map(CountdownEntity.init)
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        countdowns.map(CountdownEntity.init)
    }

    /// The next countdown to come, as a new widget shows by default.
    func defaultResult() async -> CountdownEntity? {
        WidgetStore.read()?.countdown(nil, at: .now).map(CountdownEntity.init)
    }
}

struct CountdownConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Countdown"
    static let description = IntentDescription("Choose the countdown to show.")

    /// None chosen shows the next countdown to come.
    @Parameter(title: "Countdown")
    var countdown: CountdownEntity?

    init() {}
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdown: Countdown?
    let loaded: Bool
}

struct CountdownProvider: AppIntentTimelineProvider {
    static let sample = Countdown(
        id: UUID(), label: "Home", targetAt: .now.addingTimeInterval(41 * 86_400 + 5 * 3600),
        timeZone: Zones.home)

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, countdown: Self.sample, loaded: true)
    }

    func snapshot(for configuration: CountdownConfiguration, in context: Context) async -> CountdownEntry {
        let snapshot = WidgetStore.read()
        let countdown = snapshot?.countdown(configuration.countdown?.id, at: .now)
        return CountdownEntry(
            date: .now, countdown: countdown ?? (context.isPreview ? Self.sample : nil), loaded: snapshot != nil)
    }

    /// One entry a minute for 3 hours: the clock shows days and minutes.
    func timeline(for configuration: CountdownConfiguration, in context: Context) async -> Timeline<CountdownEntry> {
        let snapshot = WidgetStore.read()
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<180).map { minute in
            let date = start.addingTimeInterval(TimeInterval(minute * 60))
            return CountdownEntry(
                date: date, countdown: snapshot?.countdown(configuration.countdown?.id, at: date),
                loaded: snapshot != nil)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "tech.abera.alarms.countdown", intent: CountdownConfiguration.self, provider: CountdownProvider()
        ) { entry in
            CountdownWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Countdown")
        .description("Days and hours to a countdown, or since it passed.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownWidgetView: View {
    let entry: CountdownEntry
    @Environment(\.widgetFamily) private var family

    private var emptyText: String { entry.loaded ? "No countdowns" : "Open Alarms to load your countdowns" }

    var body: some View {
        if let countdown = entry.countdown {
            let remaining = countdown.remaining(at: entry.date)
            switch family {
            case .accessoryInline:
                Label("\(countdown.label) \(remaining.minuteText)", systemImage: "hourglass")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(countdown.label)
                        .font(.headline)
                        .widgetAccentable()
                    Text(remaining.minuteText)
                        .monospacedDigit()
                    Text(countdown.targetText(at: entry.date))
                        .font(.caption2)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label(countdown.label, systemImage: "hourglass")
                        .font(.headline)
                        .lineLimit(2)
                    Text(remaining.minuteText)
                        .font(family == .systemSmall ? .title3.monospacedDigit() : .title.monospacedDigit())
                        .foregroundStyle(remaining.passed ? .secondary : .primary)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(countdown.targetText(at: entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if family == .accessoryInline {
            Label(emptyText, systemImage: "hourglass")
        } else {
            Text(emptyText)
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
