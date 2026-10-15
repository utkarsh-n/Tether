import SwiftUI

struct TimeTravelSheet: View {
  @Bindable var model: TetherModel
  @Environment(\.dismiss) private var dismiss
  @State private var span = 365.25
  @State private var center = 0.0
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Eyebrow(text: "An instant, reimagined")
          Text("Where in time?").font(.system(.largeTitle,design:.serif))
          Text("Readings and the entire sky follow this moment together.").foregroundStyle(.secondary)
          DatePicker("Selected instant (UT)", selection: Binding(get:{model.date},set:{model.playing=false;model.setDate($0)}), in: Date(timeIntervalSince1970:(TetherModel.minJD-2440587.5)*86400)...Date(timeIntervalSince1970:(TetherModel.maxJD-2440587.5)*86400), displayedComponents:[.date,.hourAndMinute])
            .environment(\.timeZone,TimeZone(secondsFromGMT:0)!).datePickerStyle(.compact)
          Surface {
            VStack(alignment:.leading,spacing:16) {
              Text(model.date.tetherUT).font(.headline.monospaced()).accessibilityIdentifier("selectedEpoch")
              Picker("Scrubber span",selection:$span) {
                Text("Day").tag(1.0);Text("Month").tag(30.0);Text("Year").tag(365.25);Text("200 years").tag(73413.0)
              }.pickerStyle(.segmented)
              Slider(value:Binding(get:{model.jd},set:{model.playing=false;model.setEpoch($0)}),in:range)
                .accessibilityLabel("Travel through the selected time window")
              HStack {
                Text(Date(timeIntervalSince1970:(range.lowerBound-2440587.5)*86400),format:.dateTime.year().month(.abbreviated).day())
                Spacer()
                Text(Date(timeIntervalSince1970:(range.upperBound-2440587.5)*86400),format:.dateTime.year().month(.abbreviated).day())
              }.font(.caption2).foregroundStyle(.secondary).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
              Button("Center window here") { center=model.jd }.font(.caption)
            }
          }
          GlassEffectContainer {
            HStack {
              PillAction(title:"−1 day",symbol:"minus") { model.step(-1) }
              PillAction(title:"Now",symbol:"location.fill",prominent:true) { model.now();center=model.jd }.accessibilityIdentifier("timelineNow")
              PillAction(title:"+1 day",symbol:"plus") { model.step(1) }
            }.frame(maxWidth:.infinity)
          }
          ForEach(model.profiles) { profile in
            Button {
              if let birth=try? profile.julianDay { model.setEpoch(birth);center=birth }
            } label: { Label("\(profile.name)’s arrival · \(profile.birthDate)",systemImage:"sparkle").frame(minHeight:32) }
              .tint(TetherTheme.color(profile.id)).buttonStyle(.glass)
          }
          Label("1900–2100 · verified bundled ephemeris",systemImage:"checkmark.seal").font(.footnote).foregroundStyle(.secondary)
          Text("You can explore before either birth. The birth markers remain present as enduring reference points; they are not claims about a person’s existence at that moment.")
            .font(.footnote).foregroundStyle(.secondary)
        }.padding(24)
      }.background(TetherTheme.background)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
    }.onAppear { center=model.jd;model.playing=false }
      .onChange(of:model.jd) { _,value in if !range.contains(value) { center=value } }
  }
  private var range: ClosedRange<Double> {
    let c=center == 0 ? model.jd:center
    if span>70000 { return TetherModel.minJD...TetherModel.maxJD }
    return max(TetherModel.minJD,c-span/2)...min(TetherModel.maxJD,c+span/2)
  }
}
