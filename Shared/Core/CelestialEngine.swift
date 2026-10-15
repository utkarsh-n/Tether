import Foundation
import simd

enum CelestialError: LocalizedError, Sendable {
    case outsideRange, unknownBody(String), resourceMissing(String), corruptResource(String), invalidBirthTime
    var errorDescription: String? {
        switch self {
        case .outsideRange: "Choose a date from 1900 through 2100. This app does not extrapolate beyond its ephemeris."
        case .unknownBody(let body): "Unknown celestial body: \(body)."
        case .resourceMissing(let file): "Bundled ephemeris resource is missing: \(file)."
        case .corruptResource(let file): "Bundled ephemeris resource is incomplete: \(file)."
        case .invalidBirthTime: "Enter a valid local birth date and a time in HH:mm format."
        }
    }
}

struct OrbitalState: Sendable {
    /// AU and AU/day, J2000 ecliptic. The Moon is Earth-centered; planets are Sun-centered.
    let p: SIMD3<Double>
    let v: SIMD3<Double>
}

struct CelestialBody: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let colorHex: String
    let lane: Double
    static let all: [CelestialBody] = [
        .init(id: "sun", name: "Sun", symbol: "☉", colorHex: "#f7cd83", lane: 0),
        .init(id: "moon", name: "Moon", symbol: "☽", colorHex: "#d0d9ff", lane: 2.7),
        .init(id: "mercury", name: "Mercury", symbol: "☿", colorHex: "#b4c4e1", lane: 1.2),
        .init(id: "venus", name: "Venus", symbol: "♀", colorHex: "#e7c58c", lane: 1.85),
        .init(id: "earth", name: "Earth", symbol: "⊕", colorHex: "#72bdff", lane: 2.5),
        .init(id: "mars", name: "Mars", symbol: "♂", colorHex: "#e68d72", lane: 3.15),
        .init(id: "jupiter", name: "Jupiter", symbol: "♃", colorHex: "#dfa76f", lane: 3.95),
        .init(id: "saturn", name: "Saturn", symbol: "♄", colorHex: "#d7cf93", lane: 4.75),
        .init(id: "uranus", name: "Uranus", symbol: "♅", colorHex: "#8ed4cc", lane: 5.5),
        .init(id: "neptune", name: "Neptune", symbol: "♆", colorHex: "#929cff", lane: 6.2),
        .init(id: "pluto", name: "Pluto", symbol: "♇", colorHex: "#c79ef1", lane: 7)
    ]
    static let planets = all.filter { $0.id != "sun" && $0.id != "moon" }
    static let chartBodies = all.filter { $0.id != "earth" }
}

struct Placement: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let longitude: Double
    let latitude: Double
    let distanceAU: Double
    let speedDegreesPerDay: Double
    var retrograde: Bool { speedDegreesPerDay < 0 }
    var sign: ZodiacSign { .at(longitude) }
}

struct CelestialChart: Codable, Sendable {
    let jd: Double
    let system: ZodiacSystem
    let placements: [Placement]
    let calendar: HinduCalendar
    let lunarPhase: LunarPhase
    func placement(_ id: String) -> Placement? { placements.first { $0.id == id } }
}

struct BirthProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var birthDate: String
    var place: String
    var utcOffsetMinutes: Int
    var localTime: String
    var isTimeEstimated: Bool
    var colorHex: String
    // Clearly synthetic publication examples; these are not real people or birth records.
    static let alex = BirthProfile(id: "alex", name: "Alex", birthDate: "2000-01-01", place: "Sample City A (UTC)", utcOffsetMinutes: 0, localTime: "12:00", isTimeEstimated: true, colorHex: "56D6C5")
    static let sam = BirthProfile(id: "sam", name: "Sam", birthDate: "2001-07-01", place: "Sample City B (UTC−05:00)", utcOffsetMinutes: -300, localTime: "12:00", isTimeEstimated: true, colorHex: "F49AC2")
    static let defaults = [alex, sam]
    var julianDay: Double {
        get throws {
            let parts = birthDate.split(separator: "-").compactMap { Int($0) }
            let time = localTime.split(separator: ":").compactMap { Int($0) }
            guard birthDate.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
                  localTime.range(of: #"^[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil,
                  parts.count == 3, time.count == 2,
                  (1900...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]),
                  (0...23).contains(time[0]), (0...59).contains(time[1]), abs(utcOffsetMinutes) <= 14 * 60,
                  let zone = TimeZone(secondsFromGMT: utcOffsetMinutes * 60) else { throw CelestialError.invalidBirthTime }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let components = DateComponents(timeZone: zone, year: parts[0], month: parts[1], day: parts[2], hour: time[0], minute: time[1], second: 0)
            guard let date = calendar.date(from: components) else { throw CelestialError.invalidBirthTime }
            let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard check.year == parts[0], check.month == parts[1], check.day == parts[2], check.hour == time[0], check.minute == time[1] else { throw CelestialError.invalidBirthTime }
            return AstroMath.julianDay(date)
        }
    }
}

struct BirthUncertainty: Sendable {
    let moonSigns: [String]
    let nakshatras: [String]
    var description: String { "Across the local birth date: Moon in \(moonSigns.joined(separator: " / ")); \(nakshatras.joined(separator: " / ")). Houses and ascendant are not calculated." }
}

private struct EphemerisMetadata: Decodable, Sendable {
    let id: String
    let startJD: Double
    let stopJD: Double
    let stepDays: Double
    let count: Int
    let file: String
}

private struct EphemerisTable: Sendable {
    let meta: EphemerisMetadata
    let data: Data
    func sample(jd: Double) throws -> OrbitalState {
        guard jd.isFinite, jd >= meta.startJD - 1e-9, jd <= meta.stopJD + 1e-9 else { throw CelestialError.outsideRange }
        let h = meta.stepDays
        let index = max(0, min(meta.count - 2, Int(floor((jd - meta.startJD) / h))))
        let u = AstroMath.clamp((jd - meta.startJD - Double(index) * h) / h, 0, 1)
        let u2 = u * u, u3 = u2 * u
        return data.withUnsafeBytes { bytes in
            func value(_ at: Int) -> Double {
                Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: at * 8, as: UInt64.self)))
            }
            var p = SIMD3<Double>.zero, v = SIMD3<Double>.zero
            for k in 0..<3 {
                let a = value(index * 6 + k), b = value((index + 1) * 6 + k)
                let va = value(index * 6 + k + 3), vb = value((index + 1) * 6 + k + 3)
                p[k] = (2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * h * va + (-2 * u3 + 3 * u2) * b + (u3 - u2) * h * vb
                v[k] = ((6 * u2 - 6 * u) * a + (3 * u2 - 4 * u + 1) * h * va + (-6 * u2 + 6 * u) * b + (3 * u2 - 2 * u) * h * vb) / h
            }
            return OrbitalState(p: p, v: v)
        }
    }
}

/// Immutable memory-mapped NASA/JPL Horizons state cache; safe to share between tasks.
final class CelestialEngine: Sendable {
    private let tables: [String: EphemerisTable]
    static let minimumJD = AstroMath.minJD
    static let maximumJD = AstroMath.maxJD

    convenience init(bundle: Bundle = .main) throws {
        let candidates = ["Ephemeris", "Resources/Ephemeris", "Shared/Resources/Ephemeris", "ephemeris", nil]
        let manifest = candidates.compactMap { bundle.url(forResource: "manifest", withExtension: "json", subdirectory: $0) }.first
        guard let manifest else { throw CelestialError.resourceMissing("Ephemeris/manifest.json") }
        try self.init(resourceDirectory: manifest.deletingLastPathComponent())
    }
    init(resourceDirectory: URL) throws {
        let manifestURL = resourceDirectory.appendingPathComponent("manifest.json")
        let metadata = try JSONDecoder().decode([String: EphemerisMetadata].self, from: Data(contentsOf: manifestURL))
        var loaded: [String: EphemerisTable] = [:]
        for body in CelestialBody.all where body.id != "sun" {
            guard let meta = metadata[body.id] else { throw CelestialError.resourceMissing(body.id) }
            guard meta.stepDays > 0, meta.count >= 2, meta.startJD <= AstroMath.minJD, meta.stopJD >= AstroMath.maxJD else { throw CelestialError.corruptResource(body.id) }
            let fileName = (meta.file as NSString).lastPathComponent
            let url = resourceDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { throw CelestialError.resourceMissing(fileName) }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count == meta.count * 48 else { throw CelestialError.corruptResource(fileName) }
            loaded[body.id] = EphemerisTable(meta: meta, data: data)
        }
        tables = loaded
    }
    func state(body: String, jd: Double) throws -> OrbitalState {
        guard jd.isFinite, (AstroMath.minJD...AstroMath.maxJD).contains(jd) else { throw CelestialError.outsideRange }
        if body == "sun" { return OrbitalState(p: .zero, v: .zero) }
        guard let table = tables[body] else { throw CelestialError.unknownBody(body) }
        return try table.sample(jd: jd)
    }
    func chart(jd: Double, system: ZodiacSystem = .tropical) throws -> CelestialChart {
        let earth = try state(body: "earth", jd: jd)
        let moon = try state(body: "moon", jd: jd)
        let placements = try CelestialBody.chartBodies.map { body in
            let relative: OrbitalState
            switch body.id {
            case "sun": relative = OrbitalState(p: -earth.p, v: -earth.v)
            case "moon": relative = moon
            default:
                let heliocentric = try state(body: body.id, jd: jd)
                relative = OrbitalState(p: heliocentric.p - earth.p, v: heliocentric.v - earth.v)
            }
            let longitude = AstroMath.longitude(relative.p, jd: jd, system: system)
            let ofDate = AstroMath.toDateEcliptic(relative.p, jd: jd)
            // Differentiate both the interpolated state and slow precession; no out-of-range fetch.
            let delta = 0.001
            let before = AstroMath.longitude(relative.p - relative.v * delta, jd: jd - delta, system: system)
            let after = AstroMath.longitude(relative.p + relative.v * delta, jd: jd + delta, system: system)
            return Placement(id: body.id, name: body.name, symbol: body.symbol, longitude: longitude,
                             latitude: atan2(ofDate.z, hypot(ofDate.x, ofDate.y)) / AstroMath.degrees,
                             distanceAU: simd_length(relative.p), speedDegreesPerDay: AstroMath.signedAngle(after - before) / (2 * delta))
        }
        let calendar = HinduCalendar.calculate(earth: earth.p, moon: moon.p, jd: jd)
        return CelestialChart(jd: jd, system: system, placements: placements, calendar: calendar, lunarPhase: .calculate(earth: earth.p, moon: moon.p))
    }
    func birthChart(profile: BirthProfile, system: ZodiacSystem = .tropical) throws -> CelestialChart {
        try chart(jd: profile.julianDay, system: system)
    }
    func birthAnchor(profile: BirthProfile) throws -> SIMD3<Double> {
        let sun = try -state(body: "earth", jd: profile.julianDay).p
        return simd_normalize(sun) * 8.35
    }
    func birthUncertainty(profile: BirthProfile, system: ZodiacSystem = .tropical) throws -> BirthUncertainty {
        var start = profile
        start.localTime = "00:00"
        let jd = try start.julianDay
        var signs: [String] = [], mansions: [String] = []
        for i in 0...48 {
            let instant = jd + min(Double(i) / 48, 1 - 1 / 86_400.0)
            let chart = try chart(jd: instant, system: system)
            if let moon = chart.placement("moon") {
                let name = system == .sidereal ? moon.sign.rashi : moon.sign.name
                if !signs.contains(name) { signs.append(name) }
            }
            if !mansions.contains(chart.calendar.nakshatraName) { mansions.append(chart.calendar.nakshatraName) }
        }
        return BirthUncertainty(moonSigns: signs, nakshatras: mansions)
    }
}
