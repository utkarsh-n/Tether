import SwiftUI

struct ReadingView: View {
  @Bindable var model: TetherModel
  let openTime: () -> Void
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Eyebrow(text: "Two lives. One sky.")
          Spacer()
          Image(systemName: "sparkle").foregroundStyle(TetherTheme.mint)
        }
        HStack(alignment: .top) {
          Text("A moment\nto connect.").font(.system(size: 38, weight: .medium, design: .serif)).tracking(-1)
          Spacer(minLength: 10)
          MiniZodiac(chart: model.chart).frame(width: 115, height: 115).accessibilityHidden(true)
        }
        personPicker
        EpochButton(model: model, action: openTime)
        if let reading = model.currentReading {
          Surface(accent: TetherTheme.color(model.selectedPerson)) {
            VStack(alignment: .leading, spacing: 17) {
              Eyebrow(text: "For \(model.selectedProfile.name)", color: TetherTheme.color(model.selectedPerson))
              Text(reading.headline).font(.system(.title, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
              Text(reading.summary).font(.body).foregroundStyle(.white.opacity(0.83)).lineSpacing(5)
              Divider().overlay(TetherTheme.color(model.selectedPerson).opacity(0.15))
              Label("A question to carry", systemImage: "quote.opening").font(.caption.weight(.semibold)).foregroundStyle(TetherTheme.color(model.selectedPerson))
              Text(reading.prompt).font(.system(.body, design: .serif)).italic().lineSpacing(4)
            }
          }
          VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Behind this reading").font(.headline); Spacer(); Text("SELECTED TRANSITS").font(.caption2).foregroundStyle(.secondary) }
            ForEach(reading.aspects.prefix(3)) { aspect in AspectRow(aspect: aspect, accent: TetherTheme.color(model.selectedPerson)) }
            if reading.aspects.count > 3 {
              DisclosureGroup("\(reading.aspects.count) selected alignments") {
                VStack(spacing: 12) { ForEach(reading.aspects.dropFirst(3)) { AspectRow(aspect: $0, accent: TetherTheme.violet) } }.padding(.top, 12)
              }.font(.subheadline)
            }
          }
          Text(reading.confidenceNote).font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
        }
        Text("Original astrological reflections, calculated on your device. Interpretive—not a prediction of events.")
          .font(.caption).foregroundStyle(.secondary).padding(.bottom, 18)
      }.padding(22).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
  }
  private var personPicker: some View {
    Picker("Whose reading", selection: $model.selectedPerson) {
      ForEach(model.profiles) { profile in Text(profile.name).tag(profile.id) }
    }.pickerStyle(.segmented).accessibilityIdentifier("personPicker")
  }
}

struct EpochButton: View {
  var model: TetherModel
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: "clock.arrow.circlepath").foregroundStyle(TetherTheme.violet)
        VStack(alignment: .leading, spacing: 3) {
          Text(model.date.tetherUT).font(.subheadline.weight(.medium)).monospacedDigit()
          Text("Touch to travel through time").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold))
      }.padding(15).frame(maxWidth: .infinity)
    }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
      .accessibilityLabel("Travel through time, \(model.date.tetherUT)").accessibilityIdentifier("openTimeline")
  }
}

struct AspectRow: View {
  let aspect: TransitAspect
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Image(systemName: aspect.applying ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").foregroundStyle(accent)
        Text(aspect.label).font(.subheadline.weight(.semibold))
        Spacer(minLength: 4)
        Text(String(format: "%.2f°", aspect.orb)).font(.caption.monospaced()).foregroundStyle(accent)
      }
      Text(aspect.interpretation).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
      Text("\(aspect.applying ? "Applying" : "Separating") · \(String(format: "%.2f°", aspect.separation)) separation\(aspect.timeSensitive ? " · birth time sensitive" : "")")
        .font(.caption2).foregroundStyle(.secondary)
    }.padding(16).background(.white.opacity(0.035), in: .rect(cornerRadius: 18))
  }
}

struct MiniZodiac: View {
  let chart: CelestialChart?
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width/2, y: size.height/2), r = min(size.width,size.height)*0.43
      for ratio in [0.65, 1.0] {
        let rect = CGRect(x:center.x-r*ratio,y:center.y-r*ratio,width:r*ratio*2,height:r*ratio*2)
        context.stroke(Path(ellipseIn:rect),with:.color(TetherTheme.violet.opacity(ratio == 1 ? 0.5 : 0.2)),lineWidth:1)
      }
      for i in 0..<12 {
        let a = Double(i)/12 * .pi * 2
        var path = Path(); path.move(to: CGPoint(x:center.x+cos(a)*r*0.92,y:center.y+sin(a)*r*0.92)); path.addLine(to: CGPoint(x:center.x+cos(a)*r*1.05,y:center.y+sin(a)*r*1.05))
        context.stroke(path,with:.color(.white.opacity(0.5)),lineWidth:1)
      }
      let longitudes = chart?.placements.prefix(7).map(\.longitude) ?? [10,67,93,189,248,305,348]
      for (index, longitude) in longitudes.enumerated() {
        let a = longitude * .pi / 180
        let point = CGPoint(x:center.x+cos(a)*r*0.8,y:center.y-sin(a)*r*0.8)
        var path = Path(); path.move(to:center); path.addLine(to:point)
        context.stroke(path,with:.color(TetherTheme.violet.opacity(0.2)),lineWidth:0.5)
        context.fill(Path(ellipseIn:CGRect(x:point.x-2.5,y:point.y-2.5,width:5,height:5)),with:.color(index % 2 == 0 ? TetherTheme.mint : TetherTheme.rose))
      }
      context.draw(Text("✦").font(.title3).foregroundStyle(TetherTheme.mint),at:center)
    }
  }
}
