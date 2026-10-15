import AppIntents
import SwiftUI
import WidgetKit

enum TetherWidgetPerson: String {
    case alex
    case sam

    var name: String { self == .alex ? "Alex" : "Sam" }
    var accent: Color {
        self == .alex
            ? Color(red: 0.50, green: 1.00, blue: 0.83)
            : Color(red: 1.00, green: 0.63, blue: 0.79)
    }
}

struct TetherPersonOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { ["Alex", "Sam"] }
}

struct TetherWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Daily reflection" }
    static var description: IntentDescription {
        "Choose whose personalized daily reading appears on your Home Screen."
    }

    // String options avoid an iOS 27 AppEnum resolver failure while preserving
    // the two-person picker. Lowercasing also accepts existing saved raw values.
    @Parameter(title: "Person", default: "Alex", optionsProvider: TetherPersonOptions())
    var person: String

    var selectedPerson: TetherWidgetPerson {
        TetherWidgetPerson(rawValue: person.lowercased()) ?? .alex
    }

    static var parameterSummary: some ParameterSummary {
        Summary("A daily reflection for \(\.$person)")
    }
}

struct TetherDailyEntry: TimelineEntry {
    let date: Date
    let readingDate: Date
    let person: TetherWidgetPerson
    let glyph: String
    let headline: String
    let summary: String
    let isAvailable: Bool
    let isPlaceholder: Bool

    var url: URL? {
        var components = URLComponents()
        components.scheme = "tether"
        components.host = "reading"
        components.queryItems = [
            URLQueryItem(name: "person", value: person.rawValue),
            URLQueryItem(name: "date", value: ISO8601DateFormatter().string(from: readingDate)),
        ]
        return components.url
    }

    var dateLabel: String {
        "Noon · " + readingDate.formatted(.dateTime.month(.abbreviated).day())
    }

    static func placeholder(person: TetherWidgetPerson = .alex) -> Self {
        let now = Date()
        return Self(
            date: now,
            readingDate: TetherDailyProvider.localNoon(on: now, calendar: .current),
            person: person,
            glyph: "✧",
            headline: "Your daily reflection",
            summary: "A personal reading connected to the sky, with the alignment behind every thought.",
            isAvailable: false,
            isPlaceholder: true
        )
    }
}

struct TetherDailyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TetherDailyEntry { .placeholder() }

    func snapshot(for configuration: TetherWidgetConfiguration, in context: Context) async -> TetherDailyEntry {
        let now = Date()
        return makeEntries(person: configuration.selectedPerson, dates: [now], calendar: .current)[0]
    }

    func timeline(for configuration: TetherWidgetConfiguration, in context: Context) async -> Timeline<TetherDailyEntry> {
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        // Calendar arithmetic keeps local noon and midnight correct across DST.
        let futureMidnights = (1...7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: midnight)
        }
        let entries = makeEntries(
            person: configuration.selectedPerson,
            dates: [now] + futureMidnights,
            calendar: calendar
        )
        return Timeline(entries: entries, policy: .atEnd)
    }

    static func localNoon(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private func makeEntries(person: TetherWidgetPerson, dates: [Date], calendar: Calendar) -> [TetherDailyEntry] {
        let profiles = SharedPreferences.profiles
        let profile = profiles.first(where: { $0.id == person.rawValue })
            ?? BirthProfile.defaults.first(where: { $0.id == person.rawValue })
        let system = SharedPreferences.zodiacSystem

        do {
            guard let profile else { throw WidgetReadingError.profileUnavailable }
            let engine = try CelestialEngine(bundle: .main)
            let interpreter = HoroscopeEngine(engine: engine)
            let natalChart = try engine.chart(jd: profile.julianDay, system: system)
            let glyph = natalChart.placement("sun")?.sign.symbol ?? "✧"
            return dates.map { activationDate in
                let noon = Self.localNoon(on: activationDate, calendar: calendar)
                do {
                    let reading = try interpreter.reading(
                        profile: profile,
                        jd: AstroMath.jd(from: noon),
                        system: system
                    )
                    return TetherDailyEntry(
                        date: activationDate,
                        readingDate: noon,
                        person: person,
                        glyph: glyph,
                        headline: reading.headline,
                        summary: reading.summary,
                        isAvailable: true,
                        isPlaceholder: false
                    )
                } catch {
                    return unavailable(person: person, date: activationDate, noon: noon)
                }
            }
        } catch {
            return dates.map {
                unavailable(person: person, date: $0, noon: Self.localNoon(on: $0, calendar: calendar))
            }
        }
    }

    private func unavailable(person: TetherWidgetPerson, date: Date, noon: Date) -> TetherDailyEntry {
        TetherDailyEntry(
            date: date,
            readingDate: noon,
            person: person,
            glyph: "✧",
            headline: "Reading unavailable",
            summary: "Open Tether to explore the sky and check this reading’s date and birth details.",
            isAvailable: false,
            isPlaceholder: false
        )
    }
}

private enum WidgetReadingError: Error { case profileUnavailable }

struct TetherDailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TetherDailyEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.09)
                RadialGradient(
                    colors: [entry.person.accent.opacity(0.15), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 220
                )
                WidgetOrbitDecoration(accent: entry.person.accent)
                    .opacity(0.52)
            }
        }
        .widgetURL(entry.url)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.person.name). \(entry.dateLabel), local time. \(entry.headline). \(entry.summary). \(statusLabel).")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            identity
            Text(entry.dateLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 2)
            Text(entry.headline)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            status
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                identity
                Spacer()
                Text(entry.dateLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 0)
            Text(entry.headline)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(entry.summary)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                status
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.person.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 6) {
            Text(entry.glyph)
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)
            Text(entry.person.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(entry.person.accent)
        .widgetAccentable()
    }

    private var statusLabel: String {
        if entry.isPlaceholder { return "Widget preview" }
        return entry.isAvailable ? "Symbolic interpretation" : "No reading calculated"
    }

    private var status: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isAvailable ? "sparkle" : "circle.dotted")
                .accessibilityHidden(true)
            Text(statusLabel)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(entry.person.accent.opacity(0.8))
        .lineLimit(1)
    }
}

private struct WidgetOrbitDecoration: View {
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                ForEach(0..<3) { index in
                    Ellipse()
                        .stroke(
                            LinearGradient(
                                colors: [.clear, accent.opacity(0.24), Color.purple.opacity(0.26), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 0.7
                        )
                        .frame(width: width * 0.7, height: height * 0.62)
                        .rotationEffect(.degrees(Double(index) * 32 - 42))
                }
                Circle()
                    .fill(accent.opacity(0.7))
                    .frame(width: 3, height: 3)
                    .offset(x: width * 0.25, y: -height * 0.17)
            }
            .position(x: width * 0.87, y: height * 0.63)
        }
        .accessibilityHidden(true)
    }
}

@main
struct TetherDailyWidget: Widget {
    let kind = "com.utkarsh.tether.daily"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TetherWidgetConfiguration.self,
            provider: TetherDailyProvider()
        ) { entry in
            TetherDailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily reflection")
        .description("A personal reading for Alex or Sam, grounded in the day’s alignments.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
