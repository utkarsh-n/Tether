import SwiftUI

struct MethodologyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: "A little clarity")
                    Text("The sky.\nThe story.")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .tracking(-1)
                    Text("Tether connects a calculated sky to original language for reflection. You can inspect the alignments behind each reading.")
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    method("A real sky, within a known range", symbol: "orbit", accent: TetherTheme.mint,
                           text: "The bundled NASA/JPL Horizons data supports 1900–2100. Planetary states are interpolated locally. Dates outside that range are unavailable; the app does not invent or extrapolate their positions.")
                    method("A coordinate system you can see", symbol: "scope", accent: TetherTheme.violet,
                           text: "Charts use Earth-centered, geometric positions in the mean ecliptic of the selected date. Choose the tropical zodiac or mean Lahiri sidereal zodiac. These twelve equal sectors differ from constellation boundaries. Full apparent-position corrections are not included, so small differences from other almanacs are expected.")
                    method("Interpretation, with its workings", symbol: "text.alignleft", accent: TetherTheme.rose,
                           text: "An original deterministic rules model turns natal placements and transits into prose. Aspects, orbs, and applying or separating motion are visible. The astronomy is measurable; its proposed personal meaning is an astrological reflection, not an exact prediction of events. No commercial horoscope text is downloaded.")
                    method("Birth times remain yours to confirm", symbol: "clock", accent: TetherTheme.mint,
                           text: "Alex and Sam begin with editable local-noon birth estimates. The Moon can move enough within a day to change a sign, nakshatra, or aspect. Time-sensitive readings are labeled. Houses and ascendants are not calculated, even after entering a time.")
                    method("Time, projected", symbol: "infinity", accent: TetherTheme.violet,
                           text: "The 4D and 5D views project time and orbital motion into navigable shapes. They are visual metaphors, not evidence of extra physical dimensions. Planet sizes and orbital spacing are composed for readability. The eternal personal markers and their tether are symbolic.")
                    method("A traditional cosmic calendar", symbol: "circle.hexagongrid", accent: TetherTheme.rose,
                           text: "Tithi and nakshatra follow calculated Sun–Moon geometry. The yuga explorer adopts an explicitly stated traditional epoch and 365.25-day display year. Its enormous scale is independent of the astronomical timeline and does not extend NASA’s ephemeris. Festival observances can use local sunrise and different calendar conventions.")
                    method("A daily moment on your Home Screen", symbol: "square.grid.2x2", accent: TetherTheme.mint,
                           text: "Each widget shows a reading calculated for local noon on its displayed date. Choose Alex or Sam for each widget. Tapping opens that exact moment. WidgetKit controls refresh timing; the app requests an update when saved birth details or zodiac settings change.")
                    sources
                    Text("The coordinate transforms include an adaptation of IAU SOFA routines. The original notice is included in the bundled SOFA-LICENSE.txt; this derivative is not SOFA software and is not endorsed by SOFA. All personal calculations and interpretation text run on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .padding(.bottom, 20)
                }
                .padding(22)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(TetherTheme.background)
            .navigationTitle("How Tether works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func method(_ title: String, symbol: String, accent: Color, text: String) -> some View {
        Surface(accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }

    private var sources: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Read the sources")
                source("NASA/JPL Horizons", url: "https://ssd.jpl.nasa.gov/horizons/manual.html")
                source("JPL ephemeris ranges", url: "https://ssd.jpl.nasa.gov/doc/de440_de441.html")
                source("IAU SOFA coordinate standards", url: "https://www.iausofa.org/2023-10-11c")
                source("IMD Hindu calendar conventions", url: "https://packolkata.imd.gov.in/panchang/en/explanation")
                source("Traditional yuga durations", url: "https://vedabase.io/en/library/sb/3/11/19/")
                source("Co-Star’s published method", url: "https://www.costarastrology.com/faq/")
                source("CHANI’s authored approach", url: "https://www.chani.com/app?view=home")
                Text("These references explain the methods and product research. Their authors do not endorse Tether or its interpretations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func source(_ title: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption)
                }
                .font(.subheadline)
            }
            .tint(TetherTheme.violet)
        }
    }
}
