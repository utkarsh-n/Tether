import SwiftUI

struct ConnectionView: View {
  @Bindable var model: TetherModel
  let openSettings: () -> Void
  var body: some View {
    ScrollView {
      VStack(alignment:.leading,spacing:22) {
        Eyebrow(text:"Alex + Sam")
        Text("Always in\neach other’s sky.").font(.system(size:36,weight:.medium,design:.serif)).tracking(-0.8)
        HStack(spacing:0) {
          profileOrb("alex",symbol:"♒︎")
          Rectangle().fill(LinearGradient(colors:[TetherTheme.mint,TetherTheme.violet,TetherTheme.rose],startPoint:.leading,endPoint:.trailing)).frame(height:1)
            .overlay(Image(systemName:"sparkle").foregroundStyle(TetherTheme.violet).padding(8).background(TetherTheme.background))
          profileOrb("sam",symbol:"♓︎")
        }.padding(.vertical,12).accessibilityElement(children:.ignore).accessibilityLabel("Alex and Sam’s enduring symbolic connection")
        Text(model.date.tetherUT).font(.caption.monospaced()).foregroundStyle(.secondary)
        if let shared=model.shared {
          Surface {
            VStack(alignment:.leading,spacing:16) {
              Eyebrow(text:"A shared reflection")
              Text(shared.title).font(.system(.title2,design:.serif))
              Text(shared.text).lineSpacing(5).foregroundStyle(.white.opacity(0.85))
              ForEach(shared.evidence,id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
          }
        }
        ForEach(model.profiles) { profile in
          Surface(accent:TetherTheme.color(profile.id)) {
            VStack(alignment:.leading,spacing:14) {
              HStack { Text(profile.name).font(.title2.weight(.semibold));Spacer();Eyebrow(text:profile.isTimeEstimated ? "Noon estimate":"Time supplied",color:TetherTheme.color(profile.id)) }
              Text("\(profile.birthDate) · \(profile.localTime) local\n\(profile.place)").font(.subheadline).foregroundStyle(.secondary)
              if let chart=model.natalCharts[profile.id] {
                HStack {
                  if let sun=chart.placement("sun") { natalLabel("Sun",placement:sun,system:model.system) }
                  Spacer()
                  if let moon=chart.placement("moon") { natalLabel("Moon",placement:moon,system:model.system) }
                }
                Text("\(chart.calendar.nakshatraName) · pada \(chart.calendar.pada)").font(.caption).foregroundStyle(TetherTheme.color(profile.id))
                DisclosureGroup("Birth chart alignments") {
                  VStack(spacing:12) {
                    ForEach(chart.placements) { placement in
                      HStack {
                        Text(placement.symbol).frame(width:20)
                        Text(placement.name)
                        Spacer()
                        Text("\(placement.sign.name) \(String(format:"%.2f°",placement.longitude.truncatingRemainder(dividingBy:30)))\(placement.retrograde ? " ℞":"")")
                      }.font(.caption).monospacedDigit()
                    }
                  }.padding(.top,12)
                }
              }
              if profile.isTimeEstimated,let uncertainty=model.uncertainty[profile.id] { Text(uncertainty).font(.caption).foregroundStyle(.secondary).lineSpacing(3) }
              Button("Refine birth time",action:openSettings).font(.subheadline).tint(TetherTheme.color(profile.id))
            }
          }
        }
        Text("The connection stays visible before and after both births. “Quantum tether” is a visual metaphor, not a physical measurement or a compatibility score.").font(.footnote).foregroundStyle(.secondary)
      }.padding(22).frame(maxWidth:760).frame(maxWidth:.infinity)
    }
  }
  private func profileOrb(_ id:String,symbol:String)->some View {
    VStack(spacing:10) {
      Text(model.natalCharts[id]?.placement("sun")?.sign.symbol ?? symbol).font(.system(size:34))
        .frame(width:78,height:78).background(TetherTheme.color(id).opacity(0.08),in:.circle)
        .overlay(Circle().stroke(TetherTheme.color(id).opacity(0.5),lineWidth:1))
        .shadow(color:TetherTheme.color(id).opacity(0.25),radius:15)
      Text(id.capitalized).font(.caption.weight(.medium))
    }.foregroundStyle(TetherTheme.color(id))
  }
  private func natalLabel(_ title:String,placement:Placement,system:ZodiacSystem)->some View {
    VStack(alignment:.leading,spacing:4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text("\(placement.sign.symbol) \(system == .sidereal ? placement.sign.rashi : placement.sign.name)").font(.subheadline.weight(.medium))
    }
  }
}
