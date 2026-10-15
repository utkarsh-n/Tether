import Foundation
import simd

@MainActor enum SceneBuilder {
  struct Body {
    let id: String; let symbol: String; let lane: Double; let axis: Double; let period: Double; let color: SIMD4<Float>
  }
  static let bodies: [Body] = [
    .init(id: "mercury", symbol: "☿", lane: 0.16, axis: 0.387, period: 88, color: SIMD4(0.70,0.77,0.88,1)),
    .init(id: "venus", symbol: "♀", lane: 0.24, axis: 0.723, period: 225, color: SIMD4(0.91,0.77,0.55,1)),
    .init(id: "earth", symbol: "⊕", lane: 0.33, axis: 1, period: 365.25, color: SIMD4(0.45,0.74,1,1)),
    .init(id: "mars", symbol: "♂", lane: 0.42, axis: 1.524, period: 687, color: SIMD4(0.9,0.55,0.45,1)),
    .init(id: "jupiter", symbol: "♃", lane: 0.52, axis: 5.203, period: 4333, color: SIMD4(0.87,0.65,0.44,1)),
    .init(id: "saturn", symbol: "♄", lane: 0.63, axis: 9.537, period: 10759, color: SIMD4(0.84,0.81,0.58,1)),
    .init(id: "uranus", symbol: "♅", lane: 0.73, axis: 19.19, period: 30687, color: SIMD4(0.56,0.83,0.80,1)),
    .init(id: "neptune", symbol: "♆", lane: 0.83, axis: 30.07, period: 60190, color: SIMD4(0.57,0.61,1,1)),
    .init(id: "pluto", symbol: "♇", lane: 0.94, axis: 39.48, period: 90560, color: SIMD4(0.78,0.62,0.95,1))
  ]
  static func make(engine: CelestialEngine, jd: Double, profiles: [BirthProfile], system: ZodiacSystem, mode: CosmicMode, camera: CosmicCamera, horizon: Double, geometry: Bool, zodiac: Bool) throws -> CosmicScene {
    var points: [CosmicPoint] = [.init(id: "sun", name: "Sun", position: .zero, color: SIMD4(1,0.79,0.44,1), radius: 6)]
    var paths: [CosmicPath] = []
    let temporal = mode == .worldlines || mode == .cylinder || mode == .torus
    let coveredHorizon = max(0, min(horizon, jd - TetherModel.minJD, TetherModel.maxJD - jd))
    for body in bodies {
      let state = try engine.state(body: body.id, jd: jd)
      points.append(.init(id: body.id, name: body.symbol, position: state.p * (body.lane / body.axis), color: body.color, radius: body.id == "jupiter" ? 4.5 : 3))
      var trace: [SIMD3<Double>] = []
      if temporal {
        if coveredHorizon > 0 { for i in 0...128 {
          let time = jd + (Double(i) / 64 - 1) * coveredHorizon
          trace.append(try engine.state(body: body.id, jd: time).p * (body.lane / body.axis))
        } }
      } else {
        // Instantaneous osculating ellipse is only a guide, never the time propagator.
        let gm: [String:Double] = ["mercury":22031.868551,"venus":324858.592,"earth":398600.435507,"mars":42828.375816,"jupiter":126712764.1,"saturn":37940584.8418,"uranus":5794556.4,"neptune":6836527.10058,"pluto":975.5]
        let mu = (132712440041.279419 + (gm[body.id] ?? 0)) * pow(86400,2) / pow(149597870.7,3)
        let radius = simd_length(state.p)
        let h = simd_cross(state.p, state.v)
        let ev = simd_cross(state.v, h) / mu - state.p / radius
        let eccentricity = simd_length(ev)
        let a = 1 / (2 / radius - simd_length_squared(state.v) / mu)
        let pAxis = eccentricity > 1e-10 ? simd_normalize(ev) : simd_normalize(state.p)
        let qAxis = simd_cross(simd_normalize(h), pAxis)
        for i in 0...160 {
          let angle = Double(i) / 160 * 2 * Double.pi
          trace.append((pAxis * (a * (cos(angle) - eccentricity)) + qAxis * (a * sqrt(max(0,1-eccentricity*eccentricity)) * sin(angle))) * (body.lane / body.axis))
        }
      }
      var color = body.color; color.w = temporal ? 0.56 : 0.30
      if !trace.isEmpty { paths.append(.init(points: trace, color: color, isTemporal: temporal, closed: !temporal, width: 0.65)) }
    }
    let earth = try engine.state(body: "earth", jd: jd).p * 0.33
    let moon = try engine.state(body: "moon", jd: jd).p
    points.append(.init(id: "moon", name: "Moon", position: earth + moon * 16, color: SIMD4(0.84,0.88,1,1), radius: 2))
    var anchors: [CosmicPoint] = []
    for profile in profiles {
      let birth = try profile.julianDay
      let direction = simd_normalize(-(try engine.state(body: "earth", jd: birth).p))
      anchors.append(.init(id: profile.id, name: profile.name, position: direction * 1.10, color: profile.id == "alex" ? SIMD4(0.5,1,0.83,1) : SIMD4(1,0.62,0.78,1), radius: 5))
    }
    if zodiac {
      let ring = (0...180).map { i in AstroMath.zodiacDirection(Double(i) * 2, jd: jd, system: system) * 1.22 }
      paths.append(.init(points: ring, color: SIMD4(0.65,0.58,1,0.38), closed: true, width: 0.65))
      for i in 0..<12 {
        let d = AstroMath.zodiacDirection(Double(i) * 30, jd: jd, system: system)
        paths.append(.init(points: [d*1.17,d*1.25], color: SIMD4(0.72,0.68,1,0.7), width: 1))
      }
    }
    if geometry {
      for petal in 0..<6 {
        let theta = Double(petal) * Double.pi / 3
        let center = SIMD3(cos(theta)*0.24,sin(theta)*0.24,0)
        let ring = (0...48).map { i in center + SIMD3(cos(Double(i)/48*2*Double.pi)*0.24,sin(Double(i)/48*2*Double.pi)*0.24,0) }
        paths.append(.init(points: ring, color: SIMD4(0.55,0.43,1,0.17), closed: true, width: 0.55))
      }
    }
    return CosmicScene(points: points, paths: paths, anchors: anchors, mode: mode, camera: camera)
  }
}
