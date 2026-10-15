import SwiftUI

@main
struct TetherApp: App {
  @State private var model = TetherModel()
  var body: some Scene {
    WindowGroup {
      TetherRootView(model: model)
        .preferredColorScheme(.dark)
        .tint(TetherTheme.violet)
        .task { await model.load() }
        .onOpenURL { model.handle($0) }
    }
  }
}

enum TetherSheet: String, Identifiable {
  case time, settings, methodology
  var id: String { rawValue }
}

struct TetherRootView: View {
  @Bindable var model: TetherModel
  @State private var sheet: TetherSheet?
  @Environment(\.scenePhase) private var phase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TabView(selection: $model.tab) {
      Tab("Reading", systemImage: "sparkles", value: 0) {
        navigation("Tether") { ReadingView(model: model, openTime: { sheet = .time }) }
      }
      Tab("Explore", systemImage: "globe.americas", value: 1) {
        navigation("Space & time") { ExploreView(model: model, openTime: { sheet = .time }) }
      }
      Tab("Us", systemImage: "point.3.connected.trianglepath.dotted", value: 2) {
        navigation("A shared orbit") { ConnectionView(model: model, openSettings: { sheet = .settings }) }
      }
      Tab("Cycles", systemImage: "moonphase.waning.crescent", value: 3) {
        navigation("Time within time") { CyclesView(model: model) }
      }
    }
    .sheet(item: $sheet) { item in
      switch item {
      case .time: TimeTravelSheet(model: model)
      case .settings: SettingsView(model: model)
      case .methodology: MethodologyView()
      }
    }
    .task(id: model.playing && phase == .active) {
      guard model.playing, phase == .active else { return }
      var previous = ContinuousClock.now
      while !Task.isCancelled && model.playing {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        let now = ContinuousClock.now
        let delta = previous.duration(to: now).components
        let seconds = Double(delta.seconds) + Double(delta.attoseconds) / 1e18
        previous = now
        model.setEpoch(model.jd + min(0.25, seconds) * model.daysPerSecond)
      }
    }
    .onChange(of: phase) { _, value in if value != .active { model.playing = false; OrbitalHaptics.shared.stop() } }
    .onChange(of: model.mode) { _, _ in model.rebuildScene(); OrbitalHaptics.shared.selection() }
    .onChange(of: model.horizon) { _, _ in model.rebuildScene() }
    .transaction { if reduceMotion { $0.animation = nil } }
    .overlay {
      if model.engine == nil {
        ZStack {
          TetherTheme.background.ignoresSafeArea()
          VStack(spacing: 20) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(TetherTheme.mint)
            Text("Tether").font(.largeTitle.bold())
            if let error = model.error {
              Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
              Button("Try again") { Task { await model.load() } }.buttonStyle(.glassProminent)
            } else { ProgressView("Opening your sky…") }
          }.padding(30)
        }
      }
    }
  }

  private func navigation<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .background(TetherTheme.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Model & sources", systemImage: "info.circle") { sheet = .methodology }.labelStyle(.iconOnly)
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Birth times & settings", systemImage: "slider.horizontal.3") { sheet = .settings }.labelStyle(.iconOnly)
          }
        }
    }
  }
}
