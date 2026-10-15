import XCTest
import simd
@testable import Tether

final class CoreTests: XCTestCase {
    private func engine() throws -> CelestialEngine {
        #if os(macOS)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try CelestialEngine(resourceDirectory: root.appendingPathComponent("Shared/Resources/Ephemeris"))
        #else
        return try CelestialEngine(bundle: .main)
        #endif
    }
    private func jd(_ iso: String) -> Double { AstroMath.jd(from: ISO8601DateFormatter().date(from: iso)!) }

    func testSOFAFrameOracleAndInverse() {
        // Independent official SOFA C oracle, preserved from orbital-atlas/zodiac-references.json.
        let fixtures: [(Double, SIMD3<Double>)] = [
            (2415020.5, SIMD3(0.21943079766266996, 0.7948199700494708, -0.30018550972304203)),
            (2451545, SIMD3(0.19999994306127364, 0.8000000577480816, -0.299999883964233)),
            (2461041.5, SIMD3(0.19492606215770986, 0.8012695273860803, -0.29995162072270254)),
            (2488434.499988426, SIMD3(0.1802427892877228, 0.8047515500478107, -0.2998124073573804))
        ]
        let vector = SIMD3<Double>(0.2, 0.8, -0.3)
        for (epoch, expected) in fixtures {
            let actual = AstroMath.toDateEcliptic(vector, jd: epoch)
            XCTAssertLessThan(simd_length(actual - expected), 1e-14)
            XCTAssertLessThan(simd_length(AstroMath.fromDateEcliptic(actual, jd: epoch) - vector), 1e-14)
        }
        XCTAssertEqual(AstroMath.lahiriAyanamsa(jd: 2451545), 23.85709166666667, accuracy: 1e-12)
        XCTAssertEqual(AstroMath.lahiriAyanamsa(jd: 2461041.5), 24.220303260939772, accuracy: 1e-12)
    }

    func testZodiacCompassPreservesAnglesAcrossFrames() {
        for epoch in [AstroMath.minJD, 2451545, AstroMath.maxJD] {
            for system in ZodiacSystem.allCases {
                for longitude in stride(from: 0.0, to: 360.0, by: 30) {
                    let direction = AstroMath.zodiacDirection(longitude, jd: epoch, system: system)
                    let recovered = AstroMath.meanLongitude(direction, jd: epoch, system: system)
                    XCTAssertEqual(AstroMath.separation(recovered, longitude), 0, accuracy: 1e-10)
                }
            }
        }
    }

    func testSyntheticBirthTimezoneAndValidation() throws {
        XCTAssertEqual(try BirthProfile.alex.julianDay, jd("2000-01-01T12:00:00Z"), accuracy: 1e-9)
        XCTAssertEqual(try BirthProfile.sam.julianDay, jd("2001-07-01T17:00:00Z"), accuracy: 1e-9)
        var edit = BirthProfile.sam
        edit.localTime = "02:30"
        XCTAssertEqual(try edit.julianDay, jd("2001-07-01T07:30:00Z"), accuracy: 1e-9)
        edit.localTime = "25:00"
        XCTAssertThrowsError(try edit.julianDay)
        edit.localTime = "1:001"
        XCTAssertThrowsError(try edit.julianDay)
        edit.localTime = "12:00"
        edit.birthDate = "2001-02-30"
        XCTAssertThrowsError(try edit.julianDay)
    }

    func testSyntheticBirthUncertaintyIsBounded() throws {
        let ephemeris = try engine()
        for profile in BirthProfile.defaults {
            let uncertainty = try ephemeris.birthUncertainty(profile: profile, system: .sidereal)
            XCTAssertFalse(uncertainty.moonSigns.isEmpty)
            XCTAssertFalse(uncertainty.nakshatras.isEmpty)
            XCTAssertLessThanOrEqual(uncertainty.moonSigns.count, 2)
            XCTAssertLessThanOrEqual(uncertainty.nakshatras.count, 3)
        }
    }

    func testIndependentJPLStatesAndHermiteDerivative() throws {
        let ephemeris = try engine()
        // Independent off-grid JPL Horizons requests, AU; tolerance allows measured interpolation error.
        let earth = try ephemeris.state(body: "earth", jd: 2415387)
        XCTAssertLessThan(simd_length(earth.p - SIMD3(-0.2181924043876705, 0.9586752261113262, 0.0002122577405553097)) * AstroMath.auKM, 0.2)
        let moon = try ephemeris.state(body: "moon", jd: 2415245.375)
        XCTAssertLessThan(simd_length(moon.p - SIMD3(0.002407655931504824, 0.0001585752314761909, 0.0001937208026488915)) * AstroMath.auKM, 0.92)
        let epoch = 2461316.123, h = 0.0001
        for body in ["earth", "moon", "mercury", "pluto"] {
            let center = try ephemeris.state(body: body, jd: epoch)
            let before = try ephemeris.state(body: body, jd: epoch - h)
            let after = try ephemeris.state(body: body, jd: epoch + h)
            XCTAssertLessThan(simd_length((after.p - before.p) / (2 * h) - center.v), 1e-7)
        }
    }

    func testGeocentricPlanetPositionsAndRangeGuard() throws {
        let ephemeris = try engine(), epoch = 2461316.5
        let earth = try ephemeris.state(body: "earth", jd: epoch)
        let mars = try ephemeris.state(body: "mars", jd: epoch)
        let chart = try ephemeris.chart(jd: epoch)
        XCTAssertEqual(chart.placements.count, 10)
        XCTAssertNil(chart.placement("earth"))
        XCTAssertEqual(chart.placement("mars")!.longitude, AstroMath.longitude(mars.p - earth.p, jd: epoch), accuracy: 1e-12)
        XCTAssertEqual(chart.placement("mars")!.distanceAU, simd_length(mars.p - earth.p), accuracy: 1e-12)
        for date in [AstroMath.minJD, AstroMath.maxJD] { XCTAssertEqual(try ephemeris.chart(jd: date).placements.count, 10) }
        for invalid in [AstroMath.minJD - 1, AstroMath.maxJD + 1, .nan, .infinity] {
            XCTAssertThrowsError(try ephemeris.chart(jd: invalid))
        }
    }

    func testUSNOMoonPhaseFixtures() throws {
        let ephemeris = try engine()
        let full = try ephemeris.chart(jd: 2461043.91875).lunarPhase
        XCTAssertEqual(full.name, "Full Moon")
        XCTAssertEqual(full.illumination, 0.9986105509914713, accuracy: 1e-12)
        XCTAssertEqual(full.distanceKM, 362312.3794734021, accuracy: 0.0001)
        let quarter = try ephemeris.chart(jd: 2461051.158333333).lunarPhase
        XCTAssertEqual(quarter.name, "Last Quarter")
        XCTAssertEqual(quarter.illumination, 0.5014319418982963, accuracy: 1e-10)
    }

    func testPublishedCalendarEventsAndStrictDirection() throws {
        let ephemeris = try engine()
        // IMD Positional Astronomy Centre published apparent events; model uses geometric mean.
        let fixtures: [(CelestialEvent, String)] = [(.fullMoon, "2026-06-29T23:57:00Z"), (.newMoon, "2026-07-14T09:44:00Z"), (.solarIngress, "2026-04-14T04:03:00Z")]
        for (event, iso) in fixtures {
            let expected = jd(iso)
            let forward = try XCTUnwrap(ephemeris.nextEvent(event, from: expected - 2))
            let backward = try XCTUnwrap(ephemeris.nextEvent(event, from: expected + 2, direction: -1))
            XCTAssertLessThan(abs(forward - expected) * 1440, 15)
            XCTAssertEqual(forward, backward, accuracy: 1e-7)
            let next = try XCTUnwrap(ephemeris.nextEvent(event, from: forward))
            XCTAssertGreaterThan(next - forward, 20)
        }
        XCTAssertNil(try ephemeris.nextEvent(.newMoon, from: AstroMath.minJD, direction: -1))
        XCTAssertNil(try ephemeris.nextEvent(.fullMoon, from: AstroMath.maxJD))
    }

    func testTraditionalCycleArithmeticAndSandhyas() {
        XCTAssertEqual(CosmicCalendar.yearsAt(jd: CosmicCalendar.kaliEpochJD), 0)
        XCTAssertEqual(CosmicCalendar.era(at: 0), "Kali Yuga · Manvantara 7")
        XCTAssertEqual(CosmicCalendar.era(at: -1_972_944_000), "Opening sandhya")
        XCTAssertEqual(CosmicCalendar.era(at: -1_972_944_000 + 1_728_000 + 306_720_000), "Sandhya after Manvantara 1")
        XCTAssertEqual(CosmicCalendar.yearLabel(0), "≈ 3,102 BCE")
        for cycle in CosmicCalendar.cycles {
            XCTAssertEqual(CosmicCalendar.segments(for: cycle).reduce(0) { $0 + $1.duration }, cycle.duration)
        }
    }

    func testHoroscopesAreDeterministicAndEvidenceGrounded() throws {
        let ephemeris = try engine()
        let model = HoroscopeEngine(engine: ephemeris), epoch = jd("2026-10-02T12:00:00Z")
        let first = try model.reading(profile: .alex, jd: epoch)
        let repeatRead = try model.reading(profile: .alex, jd: epoch)
        XCTAssertEqual(first.headline, repeatRead.headline)
        XCTAssertEqual(first.summary, repeatRead.summary)
        XCTAssertFalse(first.aspects.isEmpty)
        let sky = try ephemeris.chart(jd: epoch)
        let natal = try ephemeris.birthChart(profile: .alex)
        for aspect in first.aspects {
            let transit = try XCTUnwrap(sky.placement(aspect.transitBody))
            let birth = try XCTUnwrap(natal.placement(aspect.natalBody))
            let separation = AstroMath.separation(transit.longitude, birth.longitude)
            XCTAssertEqual(aspect.separation, separation, accuracy: 1e-12)
            XCTAssertEqual(aspect.orb, abs(separation - aspect.kind.angle), accuracy: 1e-12)
            XCTAssertLessThanOrEqual(aspect.orb, aspect.kind.maximumOrb)
            XCTAssertEqual(aspect.timeSensitive, aspect.natalBody == "moon")
        }
        let future = try model.reading(profile: .alex, jd: epoch + 40)
        XCTAssertNotEqual(first.aspects.map(\.id), future.aspects.map(\.id))
        let shared = try model.sharedReflection(profiles: BirthProfile.defaults, jd: epoch)
        XCTAssertTrue(shared.text.contains("Alex"))
        XCTAssertTrue(shared.text.contains("Sam"))
        XCTAssertEqual(shared.evidence.count, 2)
        XCTAssertFalse(try model.reading(profile: .alex, jd: AstroMath.minJD).summary.isEmpty)
    }
}
