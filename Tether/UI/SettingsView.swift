import SwiftUI

struct SettingsView: View {
  var model: TetherModel
  @State private var profiles:[BirthProfile]
  @State private var system:ZodiacSystem
  @State private var haptics=OrbitalHaptics.shared.enabled
  @Environment(\.dismiss) private var dismiss
  init(model:TetherModel) {
    self.model=model
    _profiles=State(initialValue:model.profiles)
    _system=State(initialValue:model.system)
  }
  var body:some View {
    NavigationStack {
      Form {
        Section("Zodiac reference") {
          Picker("Reference",selection:$system) { ForEach(ZodiacSystem.allCases,id:\.self) { Text($0.title).tag($0) } }
          Text("Tropical signs follow the equinox. Sidereal signs use the mean Lahiri convention. Neither is the irregular set of astronomical constellation boundaries.").font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(profiles.indices,id:\.self) { index in
          Section(profiles[index].name) {
            LabeledContent("Born",value:profiles[index].birthDate)
            LabeledContent("Place",value:profiles[index].place)
            Toggle("Birth time known",isOn:Binding(get:{ !profiles[index].isTimeEstimated },set:{ known in profiles[index].isTimeEstimated = !known;if !known { profiles[index].localTime="12:00" } }))
            DatePicker("Local birth time",selection:timeBinding(index),displayedComponents:.hourAndMinute)
              .environment(\.timeZone,TimeZone(secondsFromGMT:0)!).disabled(profiles[index].isTimeEstimated)
            Text(profiles[index].isTimeEstimated ? "Using local noon as an explicit estimate. Moon placements and Moon aspects may change across the day." : "Time uses the birth date’s fixed local offset: \(index == 0 ? "IST (UT+05:30)" : "CST (UT−06:00)").")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section("Feel") { Toggle("Tactile feedback",isOn:$haptics) }
        Section("Home Screen widgets") {
          Label("Touch and hold your Home Screen, choose Edit → Add Widget, then search for Tether.",systemImage:"square.grid.2x2").font(.subheadline)
          Text("Edit each widget to choose Alex or Sam. Daily readings use local noon and update through WidgetKit. Tapping opens that person and moment in the app.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Private by design") { Text("Profiles and readings stay on this device and in the app’s shared widget storage. No account, analytics, server, or horoscope subscription is required.").font(.footnote) }
      }.navigationTitle("Your sky").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement:.confirmationAction) { Button("Save") {
            model.profiles=profiles;model.system=system;OrbitalHaptics.shared.enabled=haptics
            UserDefaults.standard.set(haptics,forKey:"haptics");model.persist();dismiss()
          } }
        }
    }
  }
  private func timeBinding(_ index:Int)->Binding<Date> {
    Binding(get:{
      let parts=profiles[index].localTime.split(separator:":").compactMap { Double($0) }
      return Date(timeIntervalSince1970:(parts.first ?? 12)*3600+(parts.last ?? 0)*60)
    },set:{ date in
      var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
      profiles[index].localTime=String(format:"%02d:%02d",calendar.component(.hour,from:date),calendar.component(.minute,from:date))
    })
  }
}
