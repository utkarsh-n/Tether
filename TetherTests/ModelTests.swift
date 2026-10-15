import XCTest
@testable import Tether

@MainActor final class ModelTests: XCTestCase {
  func testDataBoundariesNeverInventTemporalHistory() throws {
    let engine = try CelestialEngine(bundle:Bundle(for: TetherModel.self))
    for jd in [AstroMath.minJD,AstroMath.maxJD] {
      for mode in [CosmicMode.worldlines,.cylinder,.torus] {
        let scene=try SceneBuilder.make(engine:engine,jd:jd,profiles:BirthProfile.defaults,system:.tropical,mode:mode,camera:CosmicCamera(),horizon:90,geometry:true,zodiac:true)
        XCTAssertFalse(scene.paths.contains(where: \.isTemporal))
        XCTAssertEqual(scene.anchors.count,2)
        XCTAssertEqual(scene.points.count,11)
      }
    }
  }
  func testTemporalEndpointsUseOnlyAvailableSymmetricDates() throws {
    let engine = try CelestialEngine(bundle:Bundle(for:TetherModel.self))
    let jd=AstroMath.minJD+1
    let scene=try SceneBuilder.make(engine:engine,jd:jd,profiles:BirthProfile.defaults,system:.tropical,mode:.torus,camera:CosmicCamera(),horizon:90,geometry:false,zodiac:false)
    let mercury=try XCTUnwrap(scene.paths.first)
    let start=try engine.state(body:"mercury",jd:AstroMath.minJD).p*(0.16/0.387)
    let stop=try engine.state(body:"mercury",jd:AstroMath.minJD+2).p*(0.16/0.387)
    XCTAssertEqual(mercury.points.first,start)
    XCTAssertEqual(mercury.points.last,stop)
  }
  func testDeepLinkSetsPersonAndAbsoluteMoment() {
    let model=TetherModel()
    model.handle(URL(string:"tether://reading?person=sam&date=2001-07-01T17:00:00Z")!)
    XCTAssertEqual(model.selectedPerson,"sam")
    XCTAssertEqual(model.jd,AstroMath.jd(from:ISO8601DateFormatter().date(from:"2001-07-01T17:00:00Z")!),accuracy:1e-9)
    XCTAssertFalse(model.playing)
    model.handle(URL(string:"https://example.com/reading?person=alex")!)
    XCTAssertEqual(model.selectedPerson,"sam")
  }
  func testClockClampAndCameraDoNotChangePhysicalEpoch() {
    let model=TetherModel()
    model.setEpoch(AstroMath.maxJD+100)
    XCTAssertEqual(model.jd,AstroMath.maxJD)
    model.updateCamera(yaw:1,pitch:0.8,zoom:100)
    XCTAssertEqual(model.jd,AstroMath.maxJD)
    XCTAssertEqual(model.camera.zoom,3)
    model.setEpoch(.nan)
    XCTAssertEqual(model.jd,AstroMath.maxJD)
  }
}
