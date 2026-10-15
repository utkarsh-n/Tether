import CoreGraphics
import Foundation
import simd

/// Display coordinates are deliberately separate from astronomical coordinates.
/// Supply normalized points (planetary extent about 1, zodiac radius about 1.15).
struct CosmicPoint: Identifiable, Equatable, Sendable {
  var id: String
  var name: String
  var position: SIMD3<Double>
  var color: SIMD4<Float>
  /// Apparent radius in screen points, independent of camera zoom.
  var radius: Float = 4
}

struct CosmicPath: Equatable, Sendable {
  var points: [SIMD3<Double>]
  var color: SIMD4<Float>
  /// Temporal samples must be evenly spaced, oldest to newest, centered on now.
  /// Spatial reference paths (zodiac, sacred geometry) leave this false.
  var isTemporal: Bool = false
  /// Only explicit display geometry should be closed. Ephemeris tracks are not
  /// joined automatically, including at the seam of the torus projection.
  var closed: Bool = false
  var width: Float = 1
}

enum CosmicMode: String, CaseIterable, Identifiable, Sendable {
  case orbit2D, orbit3D, worldlines, cylinder, torus, tracks
  var id: String { rawValue }
  var title: String {
    switch self {
    case .orbit2D: "Zodiac plane"
    case .orbit3D: "Orbital space"
    case .worldlines: "Worldlines"
    case .cylinder: "Time cylinder"
    case .torus: "Time torus"
    case .tracks: "Orbital tracks"
    }
  }
  var dimension: String {
    switch self {
    case .orbit2D: "2D"
    case .orbit3D: "3D"
    case .worldlines: "4D"
    case .cylinder, .torus, .tracks: "5D"
    }
  }
  var symbol: String {
    switch self {
    case .orbit2D: "circle"
    case .orbit3D: "globe"
    case .worldlines: "waveform.path"
    case .cylinder: "cylinder.split.1x2"
    case .torus: "circle.hexagongrid"
    case .tracks: "point.topleft.down.to.point.bottomright.curvepath"
    }
  }
  var isTimeProjection: Bool {
    self == .worldlines || self == .cylinder || self == .torus
  }
}

struct CosmicCamera: Equatable, Sendable {
  /// Radians, rotating about the ecliptic pole before tilting about screen x.
  var yaw: Double = 0
  var pitch: Double = 0.45
  var zoom: Double = 1
}

struct CosmicScene: Equatable, Sendable {
  var points: [CosmicPoint]
  var paths: [CosmicPath]
  var anchors: [CosmicPoint]
  var mode: CosmicMode
  var camera: CosmicCamera
}

/// Shared by the renderer and SwiftUI symbol/label overlays. The camera is
/// orthographic: it preserves the astronomical geometry within a chosen view.
/// Time projections below are explicit display mappings, never altered orbits.
enum CosmicProjection {
  static let framingRadius = 1.48

  static func transform(
    _ position: SIMD3<Double>, mode: CosmicMode,
    normalizedTime: Double = 0, temporal: Bool = false
  ) -> SIMD3<Double> {
    guard temporal else { return position }
    let t = min(1, max(-1, normalizedTime))
    switch mode {
    case .orbit2D, .orbit3D, .tracks:
      return position
    case .worldlines:
      return position * 0.62 + SIMD3(0, 0, t * 0.9)
    case .cylinder:
      return SIMD3(t * 1.2, position.x * 0.58, position.y * 0.58)
    case .torus:
      // The window wraps around a closed reference torus. Its sampled orbits
      // remain open when the two actual ephemeris endpoints do not coincide.
      let angle = t * Double.pi
      let radial = 0.87 + position.x * 0.29
      return SIMD3(radial * cos(angle), radial * sin(angle), position.y * 0.29)
    }
  }

  static func rotate(_ p: SIMD3<Double>, camera: CosmicCamera, mode: CosmicMode) -> SIMD3<Double> {
    let yaw = camera.yaw.isFinite ? camera.yaw : 0
    let pitch = mode == .orbit2D ? 0 : (camera.pitch.isFinite ? camera.pitch : 0)
    let x = p.x * cos(yaw) - p.y * sin(yaw)
    let y = p.x * sin(yaw) + p.y * cos(yaw)
    let z = mode == .orbit2D ? 0 : p.z
    return SIMD3(x, y * cos(pitch) - z * sin(pitch), y * sin(pitch) + z * cos(pitch))
  }

  static func project(
    _ position: SIMD3<Double>, camera: CosmicCamera, mode: CosmicMode, size: CGSize,
    normalizedTime: Double = 0, temporal: Bool = false
  ) -> CGPoint {
    let mapped = transform(position, mode: mode, normalizedTime: normalizedTime, temporal: temporal)
    let p = rotate(mapped, camera: camera, mode: mode)
    let zoom = camera.zoom.isFinite ? max(0.35, min(4, camera.zoom)) : 1
    let scale = max(1, min(size.width - 32, size.height - 40) / (2 * framingRadius)) * zoom
    return CGPoint(x: size.width * 0.5 + p.x * scale, y: size.height * 0.49 - p.y * scale)
  }

  /// Anchors are intentionally spatial reference markers in every time lens.
  /// They stay visible near the viewport edge when the camera is zoomed in.
  static func anchor(_ position: SIMD3<Double>, camera: CosmicCamera, mode: CosmicMode, size: CGSize) -> CGPoint {
    let p = project(position, camera: camera, mode: mode, size: size)
    let margin = min(22.0, min(size.width, size.height) / 2)
    return CGPoint(
      x: min(max(margin, p.x), max(margin, size.width - margin)),
      y: min(max(margin, p.y), max(margin, size.height - margin)))
  }
}
