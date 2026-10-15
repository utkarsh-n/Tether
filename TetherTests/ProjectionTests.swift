import CoreGraphics
import simd
import XCTest

@testable import Tether

final class ProjectionTests: XCTestCase {
  private let size = CGSize(width: 390, height: 450)

  private func assertPoint(
    _ actual: CGPoint, _ expected: CGPoint, accuracy: Double = 1e-10,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
  }

  func testOrthographicCameraOriginRotationAndZoom() {
    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.49)
    let camera = CosmicCamera(yaw: 0, pitch: 0, zoom: 1)
    let origin = CosmicProjection.project(.zero, camera: camera, mode: .orbit3D, size: size)
    assertPoint(origin, center)
    let right = CosmicProjection.project(SIMD3(1, 0, 0), camera: camera, mode: .orbit3D, size: size)
    let quarterTurn = CosmicProjection.project(
      SIMD3(1, 0, 0), camera: CosmicCamera(yaw: .pi / 2, pitch: 0, zoom: 1),
      mode: .orbit3D, size: size)
    assertPoint(quarterTurn, CGPoint(x: center.x, y: center.y - (right.x - center.x)))
    let magnified = CosmicProjection.project(
      SIMD3(1, 0, 0), camera: CosmicCamera(yaw: 0, pitch: 0, zoom: 2),
      mode: .orbit3D, size: size)
    XCTAssertEqual(magnified.x - center.x, 2 * (right.x - center.x), accuracy: 1e-10)
    let edgeOn = CosmicProjection.project(
      SIMD3(0, 1, 0), camera: CosmicCamera(yaw: 0, pitch: .pi / 2, zoom: 1),
      mode: .orbit3D, size: size)
    assertPoint(edgeOn, center)
  }

  func testTwoDimensionalViewFlattensDepthAndIgnoresTilt() {
    let flat = CosmicProjection.project(
      SIMD3(0.4, -0.6, 0), camera: CosmicCamera(yaw: 0.37, pitch: 0, zoom: 1),
      mode: .orbit2D, size: size)
    for depth in [-100.0, -1, 0, 1, 100] {
      for pitch in [-Double.pi, -0.5, 0, 0.75, Double.pi] {
        let projected = CosmicProjection.project(
          SIMD3(0.4, -0.6, depth), camera: CosmicCamera(yaw: 0.37, pitch: pitch, zoom: 1),
          mode: .orbit2D, size: size)
        assertPoint(projected, flat)
      }
    }
  }

  func testTemporalMappingsAreFiniteAndRespondToTime() {
    let p = SIMD3<Double>(0.7, 0.2, 0.1)
    for mode in CosmicMode.allCases {
      for step in 0...100 {
        let time = Double(step) / 50 - 1
        let mapped = CosmicProjection.transform(p, mode: mode, normalizedTime: time, temporal: true)
        XCTAssertTrue(mapped.x.isFinite && mapped.y.isFinite && mapped.z.isFinite, mode.rawValue)
        let screen = CosmicProjection.project(
          p, camera: CosmicCamera(), mode: mode, size: size,
          normalizedTime: time, temporal: true)
        XCTAssertTrue(screen.x.isFinite && screen.y.isFinite, mode.rawValue)
      }
      let past = CosmicProjection.transform(p, mode: mode, normalizedTime: -0.5, temporal: true)
      let future = CosmicProjection.transform(p, mode: mode, normalizedTime: 0.5, temporal: true)
      if mode.isTimeProjection {
        XCTAssertGreaterThan(simd_distance(past, future), 0.1, mode.rawValue)
      } else {
        XCTAssertEqual(past, p)
        XCTAssertEqual(future, p)
      }
    }
  }

  func testZodiacAndBirthAnchorsStaySpatialInEveryTimeLens() {
    let camera = CosmicCamera(yaw: 0.34, pitch: 0.46, zoom: 1)
    for index in 0..<12 {
      let angle = Double(index) * .pi / 6
      let p = SIMD3<Double>(1.22 * cos(angle), 1.22 * sin(angle), 0)
      let expected = CosmicProjection.project(p, camera: camera, mode: .orbit3D, size: size)
      for mode in CosmicMode.allCases {
        for time in [-1.0, 0, 1] {
          XCTAssertEqual(CosmicProjection.transform(p, mode: mode, normalizedTime: time), p)
        }
        // 2D intentionally removes camera tilt. All spatial and time lenses
        // share the same unmodified compass when their camera is the same.
        if mode != .orbit2D {
          assertPoint(CosmicProjection.project(p, camera: camera, mode: mode, size: size), expected)
          assertPoint(CosmicProjection.anchor(p, camera: camera, mode: mode, size: size), expected)
        }
      }
    }
  }

  func testNormalSceneFitsPhoneAndTabletWithoutAnchorClamping() {
    for viewport in [CGSize(width: 320, height: 370), CGSize(width: 430, height: 420),
                     CGSize(width: 1024, height: 600)] {
      for yaw in [0.0, 0.6, 1.7, Double.pi] {
        for pitch in [-1.2, 0.0, 0.5, 1.2] {
          let camera = CosmicCamera(yaw: yaw, pitch: pitch, zoom: 1)
          for mode in CosmicMode.allCases {
            for index in 0..<24 {
              let a = Double(index) * .pi / 12
              let ring = SIMD3<Double>(cos(a) * 1.25, sin(a) * 1.25, 0)
              let screen = CosmicProjection.project(ring, camera: camera, mode: mode, size: viewport)
              XCTAssertGreaterThan(screen.x, 0)
              XCTAssertLessThan(screen.x, viewport.width)
              XCTAssertGreaterThan(screen.y, 0)
              XCTAssertLessThan(screen.y, viewport.height)
              let anchor = SIMD3<Double>(cos(a) * 1.10, sin(a) * 1.10, 0)
              assertPoint(CosmicProjection.anchor(anchor, camera: camera, mode: mode, size: viewport),
                          CosmicProjection.project(anchor, camera: camera, mode: mode, size: viewport))
              // An envelope for the actual compressed planetary lanes,
              // including Pluto's eccentric radius and orbital inclination.
              let planet = SIMD3<Double>(cos(a) * 1.18, sin(a) * 1.18, sin(a * 2) * 0.32)
              for time in [-1.0, 0, 1] {
                let position = CosmicProjection.project(
                  planet, camera: camera, mode: mode, size: viewport,
                  normalizedTime: time, temporal: true)
                XCTAssertGreaterThan(position.x, 0, mode.rawValue)
                XCTAssertLessThan(position.x, viewport.width, mode.rawValue)
                XCTAssertGreaterThan(position.y, 0, mode.rawValue)
                XCTAssertLessThan(position.y, viewport.height, mode.rawValue)
              }
            }
          }
        }
      }
    }
  }

  func testTorusClosesTheTimeCoordinateWithoutInventingAnEphemerisClosure() {
    let p = SIMD3<Double>(0.7, 0.25, 0)
    let first = CosmicProjection.transform(p, mode: .torus, normalizedTime: -1, temporal: true)
    let last = CosmicProjection.transform(p, mode: .torus, normalizedTime: 1, temporal: true)
    XCTAssertLessThan(simd_distance(first, last), 1e-14)
    let differentEndpoint = CosmicProjection.transform(
      SIMD3(0.4, -0.3, 0), mode: .torus, normalizedTime: 1, temporal: true)
    XCTAssertGreaterThan(simd_distance(first, differentEndpoint), 0.1)
    XCTAssertFalse(CosmicPath(points: [p, differentEndpoint], color: SIMD4(1, 1, 1, 1)).closed)
  }

  func testOnlyExplicitlyClosedDisplayPathsReceiveAClosingSegment() {
    let points: [SIMD3<Double>] = [SIMD3(0.4, 0, 0), SIMD3(0, 0.4, 0), SIMD3(-0.4, 0, 0)]
    var path = CosmicPath(points: points, color: SIMD4(1, 1, 1, 1))
    var scene = CosmicScene(points: [], paths: [path], anchors: [], mode: .orbit2D, camera: CosmicCamera())
    let geometry = CosmicGeometry()
    geometry.update(scene, size: size, capacity: 1024)
    XCTAssertEqual(geometry.segments.count, 2)
    path.closed = true
    scene.paths = [path]
    geometry.update(scene, size: size, capacity: 1024)
    XCTAssertEqual(geometry.segments.count, 3)
    XCTAssertEqual(geometry.segments.last?.end, geometry.segments.first?.start)
  }

  func testDensePathsCannotConsumePersistentAnchorBudget() {
    let dense = CosmicPath(points: (0..<4000).map { SIMD3(Double($0) / 4000, 0, 0) },
                           color: SIMD4(1, 1, 1, 1))
    let anchors = [
      CosmicPoint(id: "u", name: "Alex", position: SIMD3(-0.5, 0.3, 0), color: SIMD4(0.5, 1, 0.83, 1)),
      CosmicPoint(id: "s", name: "Sam", position: SIMD3(0.5, 0.3, 0), color: SIMD4(1, 0.62, 0.78, 1))]
    let scene = CosmicScene(points: [], paths: [dense], anchors: anchors, mode: .torus, camera: CosmicCamera())
    let geometry = CosmicGeometry()
    geometry.update(scene, size: size, capacity: 1024)
    XCTAssertLessThanOrEqual(geometry.segments.count, 1024)
    XCTAssertEqual(geometry.segments.last?.color, anchors[1].color)
    XCTAssertEqual(geometry.segments.last?.style.y, 1)
    XCTAssertEqual(MemoryLayout<CosmicLineSegment>.stride, 64)
  }
}
