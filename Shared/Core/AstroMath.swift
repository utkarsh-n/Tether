import Foundation
import simd

/// Geometric mean ecliptic longitudes. This is not an apparent/topocentric almanac.
enum ZodiacSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case tropical, sidereal
    var id: String { rawValue }
    var title: String { self == .tropical ? "Tropical" : "Lahiri sidereal" }
}

struct ZodiacSign: Identifiable, Hashable, Codable, Sendable {
    let index: Int
    let degrees: Double
    var id: Int { index }
    var name: String { Self.names[index] }
    var rashi: String { Self.rashis[index] }
    var symbol: String { Self.symbols[index] }
    static let names = ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
    static let rashis = ["Mesha", "Vrishabha", "Mithuna", "Karka", "Simha", "Kanya", "Tula", "Vrishchika", "Dhanu", "Makara", "Kumbha", "Mina"]
    static let symbols = ["♈︎", "♉︎", "♊︎", "♋︎", "♌︎", "♍︎", "♎︎", "♏︎", "♐︎", "♑︎", "♒︎", "♓︎"]
    static func at(_ longitude: Double) -> ZodiacSign {
        let value = AstroMath.wrap(longitude)
        return ZodiacSign(index: min(11, Int(value / 30)), degrees: value.truncatingRemainder(dividingBy: 30))
    }
    func label(system: ZodiacSystem) -> String {
        String(format: "%@ %@ %.1f°", symbol, system == .tropical ? name : rashi, degrees)
    }
}

enum AstroMath {
    static let auKM = 149_597_870.7
    static let minJD = 2_415_020.5
    static let maxJD = 2_488_434.5 - 1 / 86_400.0
    static let degrees = Double.pi / 180
    static let arcseconds = degrees / 3_600
    static func wrap(_ angle: Double) -> Double {
        let result = angle.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
    static func signedAngle(_ angle: Double) -> Double { wrap(angle + 180) - 180 }
    static func separation(_ a: Double, _ b: Double) -> Double { abs(signedAngle(a - b)) }
    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }
    static func date(jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }
    static func jd(from date: Date) -> Double { julianDay(date) }
    static func date(fromJD jd: Double) -> Date { date(jd: jd) }
    static func clamp(_ v: Double, _ low: Double, _ high: Double) -> Double { max(low, min(high, v)) }
    static func rx(_ v: SIMD3<Double>, _ angle: Double) -> SIMD3<Double> {
        SIMD3(v.x, cos(angle) * v.y - sin(angle) * v.z, sin(angle) * v.y + cos(angle) * v.z)
    }
    static func rz(_ v: SIMD3<Double>, _ angle: Double) -> SIMD3<Double> {
        SIMD3(cos(angle) * v.x - sin(angle) * v.y, sin(angle) * v.x + cos(angle) * v.y, v.z)
    }

    // Derived from IAU SOFA 2023-10-11 iauPfw06/iauPmat06/iauEcm06/iauP06e.
    // This derivative is not SOFA software and is not endorsed by SOFA.
    // The required license and attribution are bundled in SOFA-LICENSE.txt.
    // JPL uses IAU76 J2000 obliquity (84381.448 arcsec). UT rather than TT here
    // changes the slow precession by far below .001 arcsec over 1900–2100.
    private static func fw(_ jd: Double) -> (gamma: Double, phi: Double, psi: Double) {
        let t = (jd - 2_451_545) / 36_525
        let gamma = (-0.052928 + (10.556378 + (0.4932044 + (-0.00031238 + (-0.000002788 + 0.000000026 * t) * t) * t) * t) * t) * arcseconds
        let phi = (84381.412819 + (-46.811016 + (0.0511268 + (0.00053289 + (-0.00000044 - 0.0000000176 * t) * t) * t) * t) * t) * arcseconds
        let psi = (-0.041775 + (5038.481484 + (1.5584175 + (-0.00018522 + (-0.000026452 - 0.0000000148 * t) * t) * t) * t) * t) * arcseconds
        return (gamma, phi, psi)
    }
    static func toDateEcliptic(_ vector: SIMD3<Double>, jd: Double) -> SIMD3<Double> {
        let a = fw(jd)
        return rz(rx(rz(rx(vector, 84381.448 * arcseconds), -a.gamma), -a.phi), a.psi)
    }
    static func fromDateEcliptic(_ vector: SIMD3<Double>, jd: Double) -> SIMD3<Double> {
        let a = fw(jd)
        return rx(rz(rx(rz(vector, -a.psi), a.phi), a.gamma), -84381.448 * arcseconds)
    }
    static func lahiriAyanamsa(jd: Double) -> Double {
        let t = (jd - 2_451_545) / 36_525
        let p = (5028.796195 + (1.1054348 + (0.00007964 + (-0.000023857 - 0.0000000383 * t) * t) * t) * t) * t
        return 23 + 51 / 60.0 + 25.53 / 3600 + p / 3600
    }
    static func longitude(_ vector: SIMD3<Double>, jd: Double, system: ZodiacSystem = .tropical) -> Double {
        let v = toDateEcliptic(vector, jd: jd)
        return wrap(atan2(v.y, v.x) / degrees - (system == .sidereal ? lahiriAyanamsa(jd: jd) : 0))
    }
    static func zodiacDirection(longitude: Double, jd: Double, system: ZodiacSystem = .tropical) -> SIMD3<Double> {
        let a = (longitude + (system == .sidereal ? lahiriAyanamsa(jd: jd) : 0)) * degrees
        return fromDateEcliptic(SIMD3(cos(a), sin(a), 0), jd: jd)
    }
    static func meanLongitude(_ vector: SIMD3<Double>, jd: Double, system: ZodiacSystem = .tropical) -> Double {
        longitude(vector, jd: jd, system: system)
    }
    static func zodiacDirection(_ longitude: Double, jd: Double, system: ZodiacSystem = .tropical) -> SIMD3<Double> {
        zodiacDirection(longitude: longitude, jd: jd, system: system)
    }
}

struct LunarPhase: Codable, Sendable {
    let illumination: Double
    let cosPhase: Double
    let waxing: Bool
    let longitudeDegrees: Double
    let distanceKM: Double
    let name: String
    static func calculate(earth: SIMD3<Double>, moon: SIMD3<Double>) -> LunarPhase {
        let moonToSun = -(earth + moon)
        let moonToEarth = -moon
        let c = AstroMath.clamp(simd_dot(moonToSun, moonToEarth) / (simd_length(moonToSun) * simd_length(moonToEarth)), -1, 1)
        let longitude = AstroMath.wrap((atan2(moon.y, moon.x) - atan2(-earth.y, -earth.x)) / AstroMath.degrees)
        let nearest = Int((longitude / 90).rounded())
        let primary = ["New Moon", "First Quarter", "Full Moon", "Last Quarter"]
        let name: String
        if abs(longitude - Double(nearest) * 90) <= 4 {
            name = primary[nearest % 4]
        } else {
            name = longitude < 90 ? "Waxing Crescent" : longitude < 180 ? "Waxing Gibbous" : longitude < 270 ? "Waning Gibbous" : "Waning Crescent"
        }
        return LunarPhase(illumination: (1 + c) / 2, cosPhase: c, waxing: longitude < 180, longitudeDegrees: longitude, distanceKM: simd_length(moon) * AstroMath.auKM, name: name)
    }
}
