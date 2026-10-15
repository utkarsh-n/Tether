import Foundation

/// Conventional astrological aspect angles. Their interpretation is symbolic, not a forecast.
enum AspectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case conjunction, sextile, square, trine, opposition
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var angle: Double {
        switch self { case .conjunction: 0; case .sextile: 60; case .square: 90; case .trine: 120; case .opposition: 180 }
    }
    /// Editorial choices, not astronomical error bars. These are explicitly disclosed in the app.
    var maximumOrb: Double {
        switch self { case .conjunction, .opposition: 6; case .square, .trine: 5; case .sextile: 3 }
    }
    var symbol: String {
        switch self { case .conjunction: "☌"; case .sextile: "⚹"; case .square: "□"; case .trine: "△"; case .opposition: "☍" }
    }
}

struct TransitAspect: Identifiable, Codable, Sendable {
    let id: String
    let transitBody: String
    let natalBody: String
    let transitName: String
    let natalName: String
    let kind: AspectKind
    let separation: Double
    let orb: Double
    let applying: Bool
    let timeSensitive: Bool
    let interpretation: String
    var label: String { "\(transitName) \(kind.rawValue) natal \(natalName)" }
    var evidence: String {
        String(format: "%@ · %.2f° separation · %.2f° orb · %@%@", label, separation, orb, applying ? "applying" : "separating", timeSensitive ? " · birth-time sensitive" : "")
    }
}

struct HoroscopeReading: Identifiable, Codable, Sendable {
    let id: String
    let profileID: String
    let personName: String
    let jd: Double
    let headline: String
    let summary: String
    let prompt: String
    let aspects: [TransitAspect]
    let confidenceNote: String
}

struct SharedReflection: Codable, Sendable {
    let title: String
    let text: String
    let evidence: [String]
}

/// Original, local, deterministic writing from measured transit-to-natal angles.
/// No scraped horoscope text, cloud inference, API key, or claimed predictive validity.
struct HoroscopeEngine: Sendable {
    let engine: CelestialEngine
    static let methodology = "Original symbolic reflections from geocentric mean longitudes and five major transit-to-natal aspects. Orbs: conjunction/opposition 6°, square/trine 5°, sextile 3°. These editorial conventions are not probabilities. Astrology is not scientifically established as a way to predict personality or events."

    func reading(profile: BirthProfile, jd: Double, system: ZodiacSystem = .tropical) throws -> HoroscopeReading {
        let transit = try engine.chart(jd: jd, system: system)
        let natal = try engine.birthChart(profile: profile, system: system)
        let aspects = Self.aspects(transit: transit, natal: natal, estimatedBirthTime: profile.isTimeEstimated)
        let selected = Array(aspects.prefix(5))
        let moon = transit.placement("moon")!
        let sun = transit.placement("sun")!
        let headline: String
        let summary: String
        let prompt: String
        if let first = selected.first {
            headline = Self.headline(for: first)
            let second = selected.dropFirst().first { $0.natalBody != first.natalBody } ?? selected.dropFirst().first
            summary = "\(profile.name), \(Self.lowercaseStart(first.interpretation))" + (second.map { "\n\nAlongside that, \(Self.lowercaseStart(Self.invitation($0.transitBody))) \(Self.domain($0.natalBody)). Give this need a little space before choosing your next step." } ?? "")
            prompt = Self.prompt(for: first)
        } else {
            headline = "Find your own pace"
            summary = "\(profile.name), none of the five major aspects falls within this model’s chosen orbs at this moment. The \(transit.lunarPhase.name.lowercased()) offers a simple point of reflection: notice what feels unfinished, and choose one small thing to tend.\n\nThe Sun is in \(sun.sign.name) and the Moon is in \(moon.sign.name) in the \(system.title.lowercased()) reference. Let the sky be a perspective rather than an instruction."
            prompt = "What deserves your attention when you set aside the need for a sign?"
        }
        let note = profile.isTimeEstimated
            ? "Local noon is an estimate. Natal Moon aspects can change with birth time; the most time-sensitive ones are marked. Houses and ascendant are omitted. This is a symbolic reflection, not a prediction."
            : "Uses your entered local birth time. Geometric mean positions omit light-time, aberration, and nutation. Houses and ascendant are omitted. This is a symbolic reflection, not a prediction."
        return HoroscopeReading(id: "\(profile.id)-\(String(format: "%.6f", jd))-\(system.rawValue)", profileID: profile.id, personName: profile.name,
                                jd: jd, headline: headline, summary: summary, prompt: prompt, aspects: selected, confidenceNote: note)
    }

    func sharedReflection(profiles: [BirthProfile], jd: Double, system: ZodiacSystem = .tropical) throws -> SharedReflection {
        guard profiles.count >= 2 else {
            return SharedReflection(title: "A space for connection", text: "Add both birth profiles to explore a shared reflection.", evidence: [])
        }
        let first = try reading(profile: profiles[0], jd: jd, system: system)
        let second = try reading(profile: profiles[1], jd: jd, system: system)
        let a = first.aspects.first
        let b = second.aspects.first
        let firstDomain = a.map { Self.domain($0.natalBody) } ?? "your daily rhythm"
        let secondDomain = b.map { Self.domain($0.natalBody) } ?? "your daily rhythm"
        let commonBody = first.aspects.first { item in second.aspects.contains { $0.transitBody == item.transitBody } }
        let title = commonBody.map { "Two perspectives, one \($0.transitName)" } ?? "Meet in the middle"
        let linking = commonBody.map { "\($0.transitName) appears in both of your selected aspect sets, touching each birth chart differently." } ?? "Your strongest selected aspects are different; that can be a useful metaphor for having different priorities in the same moment."
        let text = "\(linking) \(profiles[0].name), consider \(firstDomain). \(profiles[1].name), consider \(secondDomain).\n\nTrade one sentence about what you need, then repeat back what you heard before offering advice. The tether is a symbol of chosen connection, not a measured quantum effect or a compatibility score."
        let evidence = [a.map { "\(profiles[0].name): \($0.evidence)" }, b.map { "\(profiles[1].name): \($0.evidence)" }].compactMap { $0 }
        return SharedReflection(title: title, text: text, evidence: evidence)
    }

    static func aspects(transit: CelestialChart, natal: CelestialChart, estimatedBirthTime: Bool) -> [TransitAspect] {
        var result: [TransitAspect] = []
        for moving in transit.placements {
            for fixed in natal.placements {
                let separation = AstroMath.separation(moving.longitude, fixed.longitude)
                for kind in AspectKind.allCases {
                    let orb = abs(separation - kind.angle)
                    guard orb <= kind.maximumOrb else { continue }
                    let futureSeparation = AstroMath.separation(moving.longitude + moving.speedDegreesPerDay / 1440, fixed.longitude)
                    let applying = abs(futureSeparation - kind.angle) < orb
                    result.append(TransitAspect(id: "\(moving.id)-\(kind.rawValue)-\(fixed.id)", transitBody: moving.id, natalBody: fixed.id,
                                                transitName: moving.name, natalName: fixed.name, kind: kind, separation: separation, orb: orb,
                                                applying: applying, timeSensitive: estimatedBirthTime && fixed.id == "moon",
                                                interpretation: interpretation(transit: moving, natal: fixed, kind: kind, applying: applying)))
                }
            }
        }
        // Normalized proximity first. Stable tie-break makes the same sky reproducible offline.
        return result.sorted { a, b in
            let aScore = a.orb / a.kind.maximumOrb
            let bScore = b.orb / b.kind.maximumOrb
            return abs(aScore - bScore) < 1e-12 ? a.id < b.id : aScore < bScore
        }
    }

    private static func domain(_ body: String) -> String {
        switch body {
        case "sun": "the direction you want to give your life"
        case "moon": "what helps you feel at home"
        case "mercury": "the way you express and revise an idea"
        case "venus": "the care you give and receive"
        case "mars": "where you choose to put your energy"
        case "jupiter": "the possibilities you are making room for"
        case "saturn": "the commitments you want to keep"
        case "uranus": "the habits you are ready to question"
        case "neptune": "the hopes you want to put into words"
        default: "the patterns you are ready to reconsider"
        }
    }
    private static func invitation(_ body: String) -> String {
        switch body {
        case "sun": "Bring deliberate attention to"
        case "moon": "Check in gently with"
        case "mercury": "Find clearer language for"
        case "venus": "Make a little more room for"
        case "mars": "Choose one purposeful action around"
        case "jupiter": "Try a wider perspective on"
        case "saturn": "Give a workable structure to"
        case "uranus": "Allow a fresh approach to"
        case "neptune": "Separate your hopes from your assumptions about"
        default: "Look beneath the familiar story about"
        }
    }
    private static func interpretation(transit: Placement, natal: Placement, kind: AspectKind, applying: Bool) -> String {
        let opening = "\(invitation(transit.id)) \(domain(natal.id))."
        let relationship: String
        switch kind {
        case .conjunction:
            relationship = "A conjunction combines these symbolic themes; try naming a single intention instead of asking yourself to do everything at once."
        case .sextile:
            relationship = "A sextile is traditionally read as an opening. Make it concrete with a small invitation, question, or experiment."
        case .square:
            relationship = "A square offers a metaphor for competing needs. Pause long enough to name both sides before choosing your next step."
        case .trine:
            relationship = "A trine is traditionally associated with ease. Notice what already works, and give it a little intentional attention."
        case .opposition:
            relationship = "An opposition offers two viewpoints. Leave room for a different perspective without giving up your own."
        }
        let timing = applying ? "The angular gap is narrowing at this moment." : "The angular gap is widening at this moment."
        return "\(opening) \(relationship) \(timing)"
    }
    private static func headline(for aspect: TransitAspect) -> String {
        let choices: [String]
        switch aspect.kind {
        case .conjunction: choices = ["Gather your attention", "Name what matters", "Let one intention lead"]
        case .sextile: choices = ["Open a small door", "Make room for possibility", "Begin with an invitation"]
        case .square: choices = ["Make space for both needs", "Find a kinder way through", "Pause before the next step"]
        case .trine: choices = ["Notice what comes naturally", "Give ease your attention", "Build on what already works"]
        case .opposition: choices = ["Hold two perspectives", "Listen across the distance", "Meet a different rhythm"]
        }
        return choices[stableIndex(aspect.id, count: choices.count)]
    }
    private static func prompt(for aspect: TransitAspect) -> String {
        switch aspect.kind {
        case .conjunction: "What is one intention you can give your full attention to?"
        case .sextile: "What small invitation would make a possibility easier to explore?"
        case .square: "Which two needs are competing, and what would respect both?"
        case .trine: "What is quietly working that you could appreciate out loud?"
        case .opposition: "What changes when you describe the other perspective fairly?"
        }
    }
    private static func stableIndex(_ text: String, count: Int) -> Int {
        var value: UInt64 = 1469598103934665603
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return Int(value % UInt64(count))
    }
    private static func lowercaseStart(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
