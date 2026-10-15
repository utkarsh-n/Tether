import Foundation
import simd

struct HinduCalendar: Codable, Sendable {
    let sunTropical: Double
    let moonTropical: Double
    let sunSidereal: Double
    let moonSidereal: Double
    let elongation: Double
    let ayanamsa: Double
    let tithi: Int
    let paksha: String
    let tithiName: String
    let nakshatra: Int
    let pada: Int
    var tithiLabel: String { "\(paksha) \(tithiName)" }
    var nakshatraName: String { Self.nakshatras[nakshatra] }
    static let nakshatras = ["Ashvini", "Bharani", "Krittika", "Rohini", "Mrigashirsha", "Ardra", "Punarvasu", "Pushya", "Ashlesha", "Magha", "Purva Phalguni", "Uttara Phalguni", "Hasta", "Chitra", "Svati", "Vishakha", "Anuradha", "Jyeshtha", "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana", "Dhanishtha", "Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati"]
    static let tithiNames = ["Pratipada", "Dvitiya", "Tritiya", "Chaturthi", "Panchami", "Shashthi", "Saptami", "Ashtami", "Navami", "Dashami", "Ekadashi", "Dvadashi", "Trayodashi", "Chaturdashi"]
    static func calculate(earth: SIMD3<Double>, moon: SIMD3<Double>, jd: Double) -> HinduCalendar {
        let sunTropical = AstroMath.longitude(-earth, jd: jd)
        let moonTropical = AstroMath.longitude(moon, jd: jd)
        let ayanamsa = AstroMath.lahiriAyanamsa(jd: jd)
        let sunSidereal = AstroMath.wrap(sunTropical - ayanamsa)
        let moonSidereal = AstroMath.wrap(moonTropical - ayanamsa)
        let elongation = AstroMath.wrap(moonTropical - sunTropical)
        let tithi = min(30, Int(elongation / 12) + 1)
        let nakshatra = min(26, Int(moonSidereal / (360 / 27.0)))
        let pada = min(4, Int(moonSidereal.truncatingRemainder(dividingBy: 360 / 27.0) / (360 / 108.0)) + 1)
        return HinduCalendar(sunTropical: sunTropical, moonTropical: moonTropical, sunSidereal: sunSidereal, moonSidereal: moonSidereal,
                             elongation: elongation, ayanamsa: ayanamsa, tithi: tithi, paksha: tithi <= 15 ? "Shukla" : "Krishna",
                             tithiName: tithi == 15 ? "Purnima" : tithi == 30 ? "Amavasya" : tithiNames[(tithi - 1) % 15], nakshatra: nakshatra, pada: pada)
    }
}

enum CelestialEvent: String, CaseIterable, Identifiable, Sendable {
    case newMoon, fullMoon, solarIngress
    var id: String { rawValue }
    var title: String {
        switch self { case .newMoon: "New Moon"; case .fullMoon: "Full Moon"; case .solarIngress: "Solar ingress" }
    }
}

extension CelestialEngine {
    /// A geometric mean crossing estimate, not an apparent almanac or sunrise-based festival date.
    func nextEvent(_ event: CelestialEvent, from jd: Double, direction: Int = 1, system: ZodiacSystem = .sidereal) throws -> Double? {
        guard direction == 1 || direction == -1 else { return nil }
        func angle(_ date: Double) throws -> Double {
            let sky = try chart(jd: date, system: system).calendar
            return event == .solarIngress ? (system == .sidereal ? sky.sunSidereal : sky.sunTropical) : sky.elongation
        }
        let initial = try angle(jd)
        let step = event == .solarIngress ? 1.0 : 0.5
        let target = event == .solarIngress ? AstroMath.wrap((direction > 0 ? floor(initial / 30) + 1 : ceil(initial / 30) - 1) * 30) : event == .fullMoon ? 180.0 : 0.0
        var remaining = direction > 0 ? AstroMath.wrap(target - initial) : AstroMath.wrap(initial - target)
        if remaining < 1e-7 { remaining = event == .solarIngress ? 30 : 360 }
        var previousJD = jd, previousAngle = initial, traveled = 0.0
        for _ in 0..<80 {
            let nextJD = AstroMath.clamp(previousJD + Double(direction) * step, AstroMath.minJD, AstroMath.maxJD)
            if nextJD == previousJD { return nil }
            let nextAngle = try angle(nextJD)
            let arc = direction > 0 ? AstroMath.wrap(nextAngle - previousAngle) : AstroMath.wrap(previousAngle - nextAngle)
            if traveled + arc >= remaining {
                var low = previousJD, high = nextJD
                let needed = remaining - traveled
                for _ in 0..<35 {
                    let mid = (low + high) / 2
                    let midAngle = try angle(mid)
                    let delta = direction > 0 ? AstroMath.wrap(midAngle - previousAngle) : AstroMath.wrap(previousAngle - midAngle)
                    if delta < needed { low = mid } else { high = mid }
                }
                return (low + high) / 2
            }
            traveled += arc
            previousJD = nextJD
            previousAngle = nextAngle
        }
        return nil
    }
}

struct CosmicCycle: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let start: Double
    let duration: Double
    var end: Double { start + duration }
    var startLabel: String { CosmicCalendar.yearLabel(start) }
    var endLabel: String { CosmicCalendar.yearLabel(end) }
}

struct CosmicSegment: Identifiable, Sendable {
    let id: Int
    let name: String
    let duration: Double
    let isCurrent: Bool
}

/// A traditional time metaphor. These dates do not extend the physical ephemeris.
enum CosmicCalendar {
    static let kaliEpochJD = 588_465.2708333334
    static let yearDays = 365.25
    static let yugas: [CosmicCycle] = [
        .init(id: "satya", name: "Satya Yuga", start: -3_888_000, duration: 1_728_000),
        .init(id: "treta", name: "Treta Yuga", start: -2_160_000, duration: 1_296_000),
        .init(id: "dvapara", name: "Dvapara Yuga", start: -864_000, duration: 864_000),
        .init(id: "kali", name: "Kali Yuga", start: 0, duration: 432_000)
    ]
    static let cycles = yugas + [
        CosmicCycle(id: "mahayuga", name: "Mahayuga", start: -3_888_000, duration: 4_320_000),
        CosmicCycle(id: "manvantara", name: "Vaivasvata Manvantara", start: -120_528_000, duration: 306_720_000),
        CosmicCycle(id: "kalpa", name: "Kalpa", start: -1_972_944_000, duration: 4_320_000_000)
    ]
    static func yearsAt(jd: Double) -> Double { (jd - kaliEpochJD) / yearDays }
    static func yearLabel(_ offset: Double) -> String {
        let year = Int(floor(-3101 + offset))
        let number = year <= 0 ? 1 - year : year
        return "≈ \(number.formatted(.number.locale(Locale(identifier: "en_US")))) \(year <= 0 ? "BCE" : "CE")"
    }
    static func segments(for cycle: CosmicCycle) -> [CosmicSegment] {
        if yugas.contains(where: { $0.id == cycle.id }) {
            return [.init(id: 0, name: cycle.name, duration: cycle.duration, isCurrent: cycle.id == "kali")]
        }
        if cycle.id == "mahayuga" {
            return yugas.enumerated().map { .init(id: $0.offset, name: $0.element.name, duration: $0.element.duration, isCurrent: $0.element.id == "kali") }
        }
        if cycle.id == "manvantara" {
            return (0..<71).map { .init(id: $0, name: "Mahayuga \($0 + 1)", duration: 4_320_000, isCurrent: $0 == 27) }
        }
        var result: [CosmicSegment] = [.init(id: 0, name: "Opening sandhya", duration: 1_728_000, isCurrent: false)]
        for i in 0..<14 {
            result.append(.init(id: i * 2 + 1, name: "Manvantara \(i + 1)", duration: 306_720_000, isCurrent: i == 6))
            result.append(.init(id: i * 2 + 2, name: "Sandhya", duration: 1_728_000, isCurrent: false))
        }
        return result
    }
    static func era(at offset: Double) -> String {
        let kalpa = cycles[6], sandhya = 1_728_000.0
        var within = (offset - kalpa.start).truncatingRemainder(dividingBy: kalpa.duration)
        if within < 0 { within += kalpa.duration }
        if within < sandhya { return "Opening sandhya" }
        within -= sandhya
        for i in 0..<14 {
            if within < 306_720_000 {
                let phase = within.truncatingRemainder(dividingBy: 4_320_000)
                let yuga = yugas.first { phase < $0.start + 3_888_000 + $0.duration } ?? yugas[3]
                return "\(yuga.name) · Manvantara \(i + 1)"
            }
            within -= 306_720_000
            if within < sandhya { return "Sandhya after Manvantara \(i + 1)" }
            within -= sandhya
        }
        return "Kalpa boundary"
    }
}
