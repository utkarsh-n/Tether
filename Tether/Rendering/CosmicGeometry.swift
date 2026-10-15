import CoreGraphics
import Foundation
import simd

/// Binary layout mirrors CosmicGlass.metal. Each instance is one analytic line
/// capsule; a zero-length line draws a planet or a hollow anchor ring.
struct CosmicLineSegment {
  var start: SIMD2<Float>
  var end: SIMD2<Float>
  var color: SIMD4<Float>
  var style: SIMD4<Float> // radius, glow, dash period, cumulative dash offset
  var detail: SIMD4<Float> // hollow radius, reserved
}

final class CosmicGeometry {
  private(set) var segments: [CosmicLineSegment] = []
  private var capacity = 24_576
  private let referenceColor = SIMD4<Float>(0.48, 0.54, 1, 0.15)

  init() { segments.reserveCapacity(capacity) }

  func update(_ scene: CosmicScene, size: CGSize, capacity: Int) {
    // Reserve room for current bodies and the persistent personal connection
    // even if an unusually dense path snapshot reaches the GPU budget.
    self.capacity = max(0, capacity - 256)
    segments.removeAll(keepingCapacity: true)
    func project(_ p: SIMD3<Double>, time: Double = 0, temporal: Bool = false) -> SIMD2<Float> {
      let screen = CosmicProjection.project(
        p, camera: scene.camera, mode: scene.mode, size: size,
        normalizedTime: time, temporal: temporal)
      return SIMD2(Float(screen.x), Float(screen.y))
    }
    // A closed cage communicates the time mapping. This never closes or alters
    // the actual sample paths supplied by the astronomical model.
    for path in referenceCage(scene.mode) {
      draw(path, project: { project($0) })
    }
    for path in scene.paths {
      if segments.count >= self.capacity { break }
      guard path.points.count > 1 else { continue }
      var offset: Float = 0
      let denominator = Double(max(1, path.points.count - 1))
      for index in 1..<path.points.count {
        if segments.count >= self.capacity { break }
        let ta = Double(index - 1) / denominator * 2 - 1
        let tb = Double(index) / denominator * 2 - 1
        let a = project(path.points[index - 1], time: ta, temporal: path.isTemporal)
        let b = project(path.points[index], time: tb, temporal: path.isTemporal)
        var color = path.color
        let future = path.isTemporal && scene.mode.isTimeProjection && ta >= 0
        if future { color.w *= 0.72 }
        add(a, b, color: color, width: path.width, glow: path.isTemporal ? 0.2 : 0.07,
            dash: future ? 7 : 0, offset: offset)
        offset += simd_distance(a, b)
      }
      if path.closed, let first = path.points.first, let last = path.points.last {
        add(project(last, time: 1, temporal: path.isTemporal),
            project(first, time: -1, temporal: path.isTemporal),
            color: path.color, width: path.width, glow: 0.12)
      }
    }
    // Sort only the inexpensive point list; path overdraw is intentional in
    // this luminous diagram and does not imply physical planetary occlusion.
    self.capacity = capacity
    let ordered = scene.points.sorted {
      let a = CosmicProjection.transform($0.position, mode: scene.mode, temporal: true)
      let b = CosmicProjection.transform($1.position, mode: scene.mode, temporal: true)
      return CosmicProjection.rotate(a, camera: scene.camera, mode: scene.mode).z
        < CosmicProjection.rotate(b, camera: scene.camera, mode: scene.mode).z
    }
    for point in ordered {
      let p = project(point.position, temporal: true)
      add(p, p, color: point.color, width: max(2, point.radius * 2), glow: 0.9)
    }
    let anchors: [(CosmicPoint, SIMD2<Float>)] = scene.anchors.map { point in
      let p = CosmicProjection.anchor(point.position, camera: scene.camera, mode: scene.mode, size: size)
      return (point, SIMD2(Float(p.x), Float(p.y)))
    }
    if anchors.count >= 2 {
      let a = anchors[0].1
      let b = anchors[1].1
      let delta = b - a
      let length = simd_length(delta)
      let normal = length > 0.1 ? SIMD2(-delta.y, delta.x) / length : SIMD2<Float>(0, 1)
      let bow = min(38, length * 0.2)
      var previous = a
      for index in 1...56 {
        let t = Float(index) / 56
        let p = a + delta * t + normal * (sin(t * .pi) * bow)
        let color = simd_mix(anchors[0].0.color, anchors[1].0.color, SIMD4(repeating: t))
        add(previous, p, color: SIMD4(color.x, color.y, color.z, 0.78), width: 1.25, glow: 0.7)
        previous = p
      }
    }
    for (point, p) in anchors {
      add(p, p, color: SIMD4(point.color.x, point.color.y, point.color.z, 0.65),
          width: 18, glow: 0.42, hollow: 7.8)
      add(p, p, color: point.color, width: max(7, point.radius * 2), glow: 1)
    }
  }

  private func add(
    _ a: SIMD2<Float>, _ b: SIMD2<Float>, color: SIMD4<Float>, width: Float = 1,
    glow: Float = 0, dash: Float = 0, offset: Float = 0, hollow: Float = 0
  ) {
    guard segments.count < capacity, a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite,
      color.x.isFinite, color.y.isFinite, color.z.isFinite, color.w.isFinite else { return }
    segments.append(CosmicLineSegment(start: a, end: b, color: color,
      style: SIMD4(max(0.25, width * 0.5), glow, dash, offset), detail: SIMD4(hollow, 0, 0, 0)))
  }

  private func draw(_ path: CosmicPath, project: (SIMD3<Double>) -> SIMD2<Float>) {
    for index in 1..<path.points.count {
      add(project(path.points[index - 1]), project(path.points[index]), color: path.color,
          width: path.width)
    }
  }

  private func referenceCage(_ mode: CosmicMode) -> [CosmicPath] {
    var result: [CosmicPath] = []
    switch mode {
    case .cylinder:
      for index in -3...3 {
        let x = Double(index) * 0.4
        let ring = (0...64).map { step -> SIMD3<Double> in
          let a = Double(step) / 64 * .pi * 2
          return SIMD3(x, 0.6 * cos(a), 0.6 * sin(a))
        }
        var color = referenceColor
        if index == 0 { color = SIMD4(0.59, 0.7, 1, 0.45) }
        result.append(CosmicPath(points: ring, color: color, width: index == 0 ? 1.1 : 0.6))
      }
      for index in 0..<6 {
        let a = Double(index) / 6 * .pi * 2
        result.append(CosmicPath(points: [SIMD3(-1.2, 0.6 * cos(a), 0.6 * sin(a)),
                                          SIMD3(1.2, 0.6 * cos(a), 0.6 * sin(a))],
                                color: referenceColor, width: 0.6))
      }
    case .torus:
      for index in 0..<6 {
        let a = Double(index) / 6 * .pi * 2
        let line = (0...96).map { step -> SIMD3<Double> in
          let b = Double(step) / 96 * .pi * 2
          return SIMD3((0.87 + 0.3 * cos(a)) * cos(b),
                       (0.87 + 0.3 * cos(a)) * sin(b), 0.3 * sin(a))
        }
        result.append(CosmicPath(points: line, color: referenceColor, width: 0.6))
      }
      for index in 0..<12 {
        let b = Double(index) / 12 * .pi * 2
        let line = (0...40).map { step -> SIMD3<Double> in
          let a = Double(step) / 40 * .pi * 2
          return SIMD3((0.87 + 0.3 * cos(a)) * cos(b),
                       (0.87 + 0.3 * cos(a)) * sin(b), 0.3 * sin(a))
        }
        let color = index == 0 ? SIMD4<Float>(0.59, 0.7, 1, 0.45) : referenceColor
        result.append(CosmicPath(points: line, color: color, width: index == 0 ? 1.1 : 0.6))
      }
    case .worldlines:
      for index in -2...2 {
        let z = Double(index) * 0.45
        let ring = (0...64).map { step -> SIMD3<Double> in
          let a = Double(step) / 64 * .pi * 2
          return SIMD3(0.65 * cos(a), 0.65 * sin(a), z)
        }
        result.append(CosmicPath(points: ring, color: referenceColor, width: 0.6))
      }
    case .orbit2D, .orbit3D, .tracks: break
    }
    return result
  }
}
