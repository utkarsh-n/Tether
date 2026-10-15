import Foundation

enum SharedPreferences {
  static var defaults: UserDefaults { UserDefaults(suiteName: "group.com.utkarsh.tether") ?? .standard }
  static var profiles: [BirthProfile] {
    get {
      guard let data = defaults.data(forKey: "birthProfiles"),
        let result = try? JSONDecoder().decode([BirthProfile].self, from: data),
        result.map(\.id) == BirthProfile.defaults.map(\.id),
        result.allSatisfy({ (try? $0.julianDay) != nil }) else { return BirthProfile.defaults }
      return result
    }
    set { if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "birthProfiles") } }
  }
  static var zodiacSystem: ZodiacSystem {
    get { ZodiacSystem(rawValue: defaults.string(forKey: "zodiacSystem") ?? "tropical") ?? .tropical }
    set { defaults.set(newValue.rawValue, forKey: "zodiacSystem") }
  }
}
