import SwiftUI

enum TetherTheme {
  static let background = Color(red: 0.025, green: 0.031, blue: 0.065)
  static let panel = Color(red: 0.065, green: 0.073, blue: 0.13)
  static let mint = Color(red: 0.50, green: 1, blue: 0.83)
  static let rose = Color(red: 1, green: 0.62, blue: 0.78)
  static let violet = Color(red: 0.67, green: 0.58, blue: 1)
  static func color(_ id: String) -> Color { id == "alex" ? mint : rose }
}

struct Surface<Content: View>: View {
  var accent: Color = TetherTheme.violet
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
      .background(TetherTheme.panel.gradient, in: .rect(cornerRadius: 26))
      .overlay(RoundedRectangle(cornerRadius: 26).stroke(accent.opacity(0.16), lineWidth: 1))
  }
}

struct Eyebrow: View {
  let text: String
  var color: Color = TetherTheme.violet
  var body: some View { Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(2).foregroundStyle(color) }
}

struct PillAction: View {
  let title: String
  let symbol: String
  var tint: Color = TetherTheme.violet
  var prominent = false
  let action: () -> Void
  var body: some View {
    Group {
      if prominent { button.buttonStyle(.glassProminent) }
      else { button.buttonStyle(.glass) }
    }.tint(tint).buttonBorderShape(.capsule)
  }
  var button: some View {
    Button { OrbitalHaptics.shared.tap(); action() } label: {
      Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).frame(minHeight: 30)
    }
  }
}

extension Date {
  var tetherUT: String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "d MMM yyyy · HH:mm 'UT'"
    return f.string(from: self)
  }
}
