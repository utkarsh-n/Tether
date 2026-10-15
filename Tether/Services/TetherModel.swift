import Foundation
import Observation
import WidgetKit

@MainActor @Observable
final class TetherModel {
  var engine: CelestialEngine?
  var error: String?
  var jd = Date().timeIntervalSince1970 / 86400 + 2440587.5
  var profiles = SharedPreferences.profiles
  var system = SharedPreferences.zodiacSystem
  var selectedPerson = "alex"
  var tab = 0
  var playing = false
  var daysPerSecond = 2.0
  var horizon = 90.0
  var mode: CosmicMode = .orbit3D
  var camera = CosmicCamera()
  var chart: CelestialChart?
  var readings: [String: HoroscopeReading] = [:]
  var natalCharts: [String: CelestialChart] = [:]
  var uncertainty: [String: String] = [:]
  var shared: SharedReflection?
  var scene = CosmicScene(points: [], paths: [], anchors: [], mode: .orbit3D, camera: CosmicCamera())
  var sacredGeometry = true
  var showZodiac = true
  var rendererError: String?
  init() {
    if let enabled = UserDefaults.standard.object(forKey: "haptics") as? Bool { OrbitalHaptics.shared.enabled = enabled }
  }
  static let minJD = 2415020.5
  static let maxJD = 2488434.5 - 1 / 86400.0
  var date: Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }
  var selectedProfile: BirthProfile { profiles.first { $0.id == selectedPerson } ?? profiles[0] }
  var currentReading: HoroscopeReading? { readings[selectedPerson] }
  var effectiveHorizon: Double { max(0, min(horizon, jd - Self.minJD, Self.maxJD - jd)) }

  func load() async {
    guard engine == nil else { return }
    do {
      engine = try await Task.detached(priority: .userInitiated) { try CelestialEngine() }.value
      updateBirthCharts()
      refresh()
    } catch { self.error = error.localizedDescription }
  }

  func setEpoch(_ value: Double) {
    guard value.isFinite else { return }
    jd = min(Self.maxJD, max(Self.minJD, value))
    if jd == Self.minJD || jd == Self.maxJD { playing = false }
    refresh()
  }
  func setDate(_ date: Date) { setEpoch(date.timeIntervalSince1970 / 86400 + 2440587.5) }
  func now() { playing = false; setDate(Date()) }
  func step(_ days: Double) { playing = false; setEpoch(jd + days); OrbitalHaptics.shared.selection() }
  func refresh() {
    guard let engine else { return }
    do {
      chart = try engine.chart(jd: jd, system: system)
      let interpreter = HoroscopeEngine(engine: engine)
      for profile in profiles { readings[profile.id] = try interpreter.reading(profile: profile, jd: jd, system: system) }
      shared = try interpreter.sharedReflection(profiles: profiles, jd: jd, system: system)
      rebuildScene()
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  func rebuildScene() {
    guard let engine else { return }
    do { scene = try SceneBuilder.make(engine: engine, jd: jd, profiles: profiles, system: system, mode: mode, camera: camera, horizon: horizon, geometry: sacredGeometry, zodiac: showZodiac) }
    catch { self.error = error.localizedDescription }
  }
  func updateCamera(yaw: Double? = nil, pitch: Double? = nil, zoom: Double? = nil) {
    if let yaw { camera.yaw = yaw }
    if let pitch { camera.pitch = min(Double.pi / 2, max(-Double.pi / 2, pitch)) }
    if let zoom { camera.zoom = min(3, max(0.5, zoom)) }
    scene.camera = camera
  }
  func resetCamera() { camera = CosmicCamera(); scene.camera = camera }
  func persist() {
    SharedPreferences.profiles = profiles
    SharedPreferences.zodiacSystem = system
    WidgetCenter.shared.reloadAllTimelines()
    updateBirthCharts()
    refresh()
  }
  func updateBirthCharts() {
    guard let engine else { return }
    for profile in profiles {
      natalCharts[profile.id] = try? engine.birthChart(profile: profile, system: system)
      uncertainty[profile.id] = (try? engine.birthUncertainty(profile: profile, system: system))?.description
    }
  }
  func handle(_ url: URL) {
    guard url.scheme == "tether", url.host == "reading", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
    let items = components.queryItems ?? []
    if let person = items.first(where: { $0.name == "person" })?.value, profiles.contains(where: { $0.id == person }) { selectedPerson = person }
    if let value = items.first(where: { $0.name == "date" })?.value, let date = ISO8601DateFormatter().date(from: value) { setDate(date) }
    tab = 0; playing = false
  }
}
