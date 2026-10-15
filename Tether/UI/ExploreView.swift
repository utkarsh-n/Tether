import SwiftUI

struct ExploreView: View {
  @Bindable var model: TetherModel
  let openTime: () -> Void
  @State private var gestureCamera: CosmicCamera?
  @State private var initialZoom: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let signs = ["♈︎","♉︎","♊︎","♋︎","♌︎","♍︎","♎︎","♏︎","♐︎","♑︎","♒︎","♓︎"]
  var body: some View {
    GeometryReader { viewport in
      ScrollView {
        VStack(spacing: 14) {
          ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(CosmicMode.allCases) { mode in
                  Button { model.mode = mode } label: {
                    VStack(spacing: 4) {
                      Text(mode.dimension).font(.caption.bold())
                      Text(mode.title).font(.caption2).lineLimit(1)
                    }.padding(.horizontal, 14).frame(height: 44)
                      .foregroundStyle(model.mode == mode ? .white : .secondary)
                      .background(model.mode == mode ? TetherTheme.violet.opacity(0.28) : .white.opacity(0.04), in: .capsule)
                  }.buttonStyle(.plain).accessibilityIdentifier("mode_\(mode.rawValue)").id(mode)
                }
              }.padding(.horizontal, 18)
            }
            .accessibilityIdentifier("projectionSelector")
            .onChange(of: model.mode) { _, value in withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) } }
          }
          EpochButton(model: model, action: openTime).padding(.horizontal, 18)
          ZStack {
            CosmicMetalView(scene: model.scene, onError: { model.rendererError = $0 })
            GeometryReader { geometry in labels(size: geometry.size) }.allowsHitTesting(false)
            if let error = model.rendererError {
              ContentUnavailableView("Renderer unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            }
          }
          .frame(height: max(300, min(600, viewport.size.height - 350)))
          .clipShape(.rect(cornerRadius: 28))
          .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
              Eyebrow(text: model.mode.dimension + " / " + model.mode.title)
              Text("\(Int(model.camera.yaw * 180 / .pi))° az · \(Int(model.camera.pitch * 180 / .pi))° el")
                .font(.caption2.monospaced()).foregroundStyle(.secondary).accessibilityIdentifier("cameraReadout")
            }.padding(18).allowsHitTesting(false)
          }
          .contentShape(Rectangle())
          .highPriorityGesture(DragGesture(minimumDistance: 3).onChanged { value in
            if gestureCamera == nil { gestureCamera = model.camera }
            guard let initial = gestureCamera else { return }
            model.updateCamera(yaw: initial.yaw + value.translation.width * 0.009, pitch: initial.pitch + value.translation.height * 0.009)
          }.onEnded { _ in gestureCamera = nil })
          .simultaneousGesture(MagnifyGesture().onChanged { value in
            if initialZoom == nil { initialZoom = model.camera.zoom }
            model.updateCamera(zoom: (initialZoom ?? 1) * value.magnification)
          }.onEnded { _ in initialZoom = nil })
          .onTapGesture(count: 2) { model.resetCamera() }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(model.mode.title). Nine planetary paths, the Moon, Alex and Sam joined by a symbolic tether.")
          .accessibilityValue("Azimuth \(Int(model.camera.yaw*180 / .pi)) degrees, tilt \(Int(model.camera.pitch*180 / .pi)) degrees, zoom \(Int(model.camera.zoom*100)) percent")
          .accessibilityAdjustableAction { direction in model.updateCamera(yaw: model.camera.yaw + (direction == .increment ? 0.15 : -0.15)) }
          .accessibilityAction(named: "Zoom in") { model.updateCamera(zoom: model.camera.zoom*1.2) }
          .accessibilityAction(named: "Zoom out") { model.updateCamera(zoom: model.camera.zoom/1.2) }
          .accessibilityAction(named: "Reset camera") { model.resetCamera() }
          .accessibilityIdentifier("cosmicCanvas")
          .padding(.horizontal, 10)
          HStack(spacing: 8) {
            Circle().fill(TetherTheme.mint).frame(width: 5,height:5); Text("Alex")
            Text("⟷").foregroundStyle(TetherTheme.violet)
            Text("Sam"); Circle().fill(TetherTheme.rose).frame(width: 5,height:5)
            Spacer(); Text("Drag · pinch · double-tap").foregroundStyle(.secondary)
          }.font(.caption2).padding(.horizontal, 22)
          transport.padding(.horizontal, 18)
          if model.mode.isTimeProjection {
            HStack { Text("Time window").font(.caption); Picker("Time window", selection: $model.horizon) {
              Text("±30 days").tag(30.0); Text("±90 days").tag(90.0); Text("±1 year").tag(365.25)
            }.pickerStyle(.segmented) }.padding(.horizontal, 18)
            if model.effectiveHorizon < model.horizon {
              Text("Data boundary: this view covers ±\(model.effectiveHorizon, specifier: "%.2f") days.").font(.caption).foregroundStyle(TetherTheme.rose)
            }
          }
          HStack {
            Toggle("Zodiac", isOn: $model.showZodiac)
            Toggle("Geometry", isOn: $model.sacredGeometry)
          }.font(.caption).padding(.horizontal,22).tint(TetherTheme.violet)
            .onChange(of: model.showZodiac) { _,_ in model.rebuildScene() }
            .onChange(of: model.sacredGeometry) { _,_ in model.rebuildScene() }
          Text(model.mode.isTimeProjection ? "Time is projected into shape. The torus reference closes; real trajectories retain their distinct endpoints. 5D is an exploratory lens, not a fifth physical dimension." : "Heliocentric ephemeris · individually scaled orbits · artistic body sizes. Zodiac directions are geocentric sky references. Birth markers and the tether are symbolic.")
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 18)
          if let chart=model.chart {
            DisclosureGroup("Current sky · \(model.system.title)") {
              VStack(spacing:14) {
                ForEach(chart.placements) { placement in
                  HStack {
                    Text(placement.symbol).frame(width:20)
                    Text(placement.name)
                    Spacer()
                    Text(placement.sign.label(system:model.system) + (placement.retrograde ? " ℞":""))
                  }.font(.caption).monospacedDigit()
                }
                Text("Geocentric mean longitudes · ℞ apparent retrograde motion").font(.caption2).foregroundStyle(.secondary)
              }.padding(.top,14)
            }.padding(.horizontal,22).padding(.bottom,22)
          }
        }.padding(.top, 8).frame(maxWidth: 1000).frame(maxWidth: .infinity)
      }
    }
  }
  private var transport: some View {
    VStack(spacing: 12) {
      GlassEffectContainer {
        HStack {
          Button("Previous day", systemImage: "backward.end.fill") { model.step(-1) }.labelStyle(.iconOnly)
          Button(model.playing ? "Pause" : "Play", systemImage: model.playing ? "pause.fill" : "play.fill") { model.playing.toggle(); OrbitalHaptics.shared.tap() }
            .accessibilityIdentifier("playTimeline")
          Button("Next day", systemImage: "forward.end.fill") { model.step(1) }.labelStyle(.iconOnly)
          Spacer()
          Button("Reset camera", systemImage: "viewfinder") { model.resetCamera() }.labelStyle(.iconOnly)
          Button("Now") { model.now() }
        }.buttonStyle(.glass).controlSize(.regular)
      }
      HStack {
        Text("Rate").font(.caption).foregroundStyle(.secondary)
        Picker("Playback rate", selection: $model.daysPerSecond) {
          Text("1 h/s").tag(1.0/24); Text("2 d/s").tag(2.0); Text("30 d/s").tag(30.0); Text("1 y/s").tag(365.25)
        }.pickerStyle(.segmented)
      }
    }
  }
  @ViewBuilder private func labels(size: CGSize) -> some View {
    if model.showZodiac {
      ForEach(0..<12) { i in
        let direction = AstroMath.zodiacDirection(Double(i)*30+15, jd: model.jd, system: model.system)*1.34
        let p = CosmicProjection.project(direction, camera: model.camera, mode: model.mode, size: size)
        Text(signs[i]).font(.system(size: 15)).foregroundStyle(TetherTheme.violet.opacity(0.9)).position(p)
      }
    }
    ForEach(model.scene.anchors) { anchor in
      let p = CosmicProjection.anchor(anchor.position, camera: model.camera, mode: model.mode, size: size)
      Text(anchor.name).font(.caption2.weight(.semibold)).foregroundStyle(TetherTheme.color(anchor.id))
        .position(x: min(size.width-30,max(30,p.x)),y: min(size.height-10,p.y+17))
    }
  }
}
