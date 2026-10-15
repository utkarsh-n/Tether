import SwiftUI

struct CyclesView: View {
    var model: TetherModel
    @State private var cycleID = "kali"
    @State private var linkedToMoment = true
    @State private var symbolicYears = 0.0
    @State private var searching = false
    @State private var eventMessage: String?

    private var cycle: CosmicCycle {
        CosmicCalendar.cycles.first { $0.id == cycleID } ?? CosmicCalendar.yugas[3]
    }
    private var displayedYears: Double {
        linkedToMoment ? CosmicCalendar.yearsAt(jd: model.jd) : symbolicYears
    }
    private var progress: Double {
        AstroMath.clamp((displayedYears - cycle.start) / cycle.duration, 0, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "The rhythm of the sky", color: TetherTheme.mint)
                Text("Small moments.\nVast cycles.")
                    .font(.system(size: 38, weight: .medium, design: .serif))
                    .tracking(-1)
                Text(model.date.tetherUT)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cyclesEpoch")

                if let chart = model.chart {
                    lunarSurface(chart)
                    calendarSurface(chart.calendar)
                    eventSurface
                } else {
                    Surface {
                        Label("Loading the celestial calendar…", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                }
                cosmicSurface
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private func lunarSurface(_ chart: CelestialChart) -> some View {
        Surface(accent: TetherTheme.mint) {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(text: "Sun + Moon in sync", color: TetherTheme.mint)
                SolarLunarDial(calendar: chart.calendar, phase: chart.lunarPhase)
                    .frame(height: 225)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Solar longitude \(chart.calendar.sunTropical, specifier: "%.1f") degrees. Lunar elongation \(chart.calendar.elongation, specifier: "%.1f") degrees.")
                HStack(alignment: .firstTextBaseline) {
                    Text(chart.lunarPhase.name)
                        .font(.system(.title2, design: .serif).weight(.medium))
                    Spacer(minLength: 8)
                    Text(chart.lunarPhase.illumination.formatted(.percent.precision(.fractionLength(1))))
                        .font(.title3.monospacedDigit().weight(.medium))
                        .foregroundStyle(TetherTheme.mint)
                }
                HStack {
                    Label("Solar longitude", systemImage: "sun.max.fill")
                        .foregroundStyle(Color(red: 1, green: 0.81, blue: 0.48))
                    Spacer()
                    Label("Lunar elongation", systemImage: "moon.fill")
                        .foregroundStyle(TetherTheme.mint)
                }
                .font(.caption2)
                Text("Illuminated fraction viewed from Earth. The inner ring follows the Moon’s phase; the outer ring follows the Sun through the tropical year.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private func calendarSurface(_ calendar: HinduCalendar) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Hindu celestial calendar")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                    calendarValue("Tithi · \(calendar.tithi)/30", value: calendar.tithiLabel)
                    calendarValue("Nakshatra · pada \(calendar.pada)", value: calendar.nakshatraName)
                    calendarValue("Solar rashi", value: ZodiacSign.at(calendar.sunSidereal).label(system: .sidereal))
                    calendarValue("Lunar rashi", value: ZodiacSign.at(calendar.moonSidereal).label(system: .sidereal))
                }
                Divider()
                Text("Mean Lahiri ayanamsa \(calendar.ayanamsa, specifier: "%.3f")° · Geocentric positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("These are instantaneous astronomical divisions. Festival dates also depend on local sunrise and calendar traditions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    private func calendarValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventSurface: some View {
        Surface(accent: TetherTheme.mint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(text: "Find the next turning point", color: TetherTheme.mint)
                    Spacer()
                    if searching { ProgressView().controlSize(.small) }
                }
                ForEach(CelestialEvent.allCases) { event in
                    PillAction(
                        title: "Next \(event.title)",
                        symbol: eventSymbol(event),
                        tint: event == .solarIngress ? TetherTheme.violet : TetherTheme.mint
                    ) { jump(to: event) }
                    .disabled(searching || model.engine == nil)
                    .accessibilityIdentifier("next-\(event.rawValue)")
                }
                Text(eventMessage ?? "Jumps the shared timeline to a geometric crossing estimate. Solar ingress follows \(model.system.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .accessibilityIdentifier("cycleEventMessage")
            }
        }
    }

    private func eventSymbol(_ event: CelestialEvent) -> String {
        switch event {
        case .newMoon: "moon"
        case .fullMoon: "moon.fill"
        case .solarIngress: "sun.max"
        }
    }

    private func jump(to event: CelestialEvent) {
        guard let engine = model.engine, !searching else { return }
        searching = true
        let date = model.jd
        let system = model.system
        Task {
            do {
                let next = try await Task.detached(priority: .userInitiated) {
                    try engine.nextEvent(event, from: date, direction: 1, system: system)
                }.value
                if let next {
                    model.playing = false
                    model.setEpoch(next)
                    eventMessage = "\(event.title) · \(AstroMath.date(jd: next).tetherUT). Geometric estimate."
                } else {
                    eventMessage = "No later \(event.title.lowercased()) is available before the end of 2100."
                }
            } catch {
                eventMessage = error.localizedDescription
            }
            searching = false
        }
    }

    private var cosmicSurface: some View {
        Surface(accent: TetherTheme.rose) {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Traditional cosmic time", color: TetherTheme.rose)
                Text("A larger circle.")
                    .font(.system(.title, design: .serif).weight(.medium))
                Text("Explore the Hindu cycles of time on their own scale.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Cosmic cycle", selection: Binding(
                    get: { cycleID },
                    set: { value in
                        cycleID = value
                        linkedToMoment = false
                        symbolicYears = cycle.start
                        OrbitalHaptics.shared.selection()
                    }
                )) {
                    ForEach(CosmicCalendar.cycles) { cycle in Text(cycle.name).tag(cycle.id) }
                }
                .pickerStyle(.menu)
                .tint(TetherTheme.rose)
                .accessibilityIdentifier("cosmicCyclePicker")
                VStack(alignment: .leading, spacing: 6) {
                    Text(CosmicCalendar.yearLabel(displayedYears))
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("cosmicYear")
                    Text(CosmicCalendar.era(at: displayedYears))
                        .font(.subheadline)
                        .foregroundStyle(TetherTheme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CycleBand(cycle: cycle, progress: progress)
                    .frame(height: 27)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { progress },
                        set: {
                            linkedToMoment = false
                            symbolicYears = cycle.start + cycle.duration * $0
                            OrbitalHaptics.shared.detent(normalized: $0)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: {
                        if $0 { OrbitalHaptics.shared.beginAdjustment() }
                        else { OrbitalHaptics.shared.endAdjustment() }
                    }
                ) {
                    Text("Explore \(cycle.name)")
                }
                .tint(TetherTheme.rose)
                .accessibilityValue(CosmicCalendar.yearLabel(displayedYears))
                .accessibilityIdentifier("cosmicScrubber")
                HStack(alignment: .top, spacing: 12) {
                    Text(cycle.startLabel).frame(maxWidth: .infinity, alignment: .leading)
                    Text(cycle.endLabel).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                Text("\(Int(cycle.duration).formatted()) traditional years · \(progress.formatted(.percent.precision(.fractionLength(2)))) traversed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PillAction(title: "Align with this moment", symbol: "scope", tint: TetherTheme.rose) {
                    let current = CosmicCalendar.yearsAt(jd: model.jd)
                    if current < cycle.start || current > cycle.end { cycleID = "kali" }
                    linkedToMoment = true
                }
                Text(linkedToMoment ? "Linked to the selected astronomical moment." : "Independent symbolic exploration. The sky and readings keep their selected date.")
                    .font(.caption)
                    .foregroundStyle(TetherTheme.rose.opacity(0.9))
                DisclosureGroup("Epoch and cycle conventions") {
                    Text("Kali Yuga begins at the traditional epoch 18 February 3102 BCE, 00:00 IST, in the proleptic Julian calendar. Large year labels use 365.25 days per display year. The adopted scheme places the present in the 28th Mahayuga of the 7th Manvantara. A Kalpa includes 14 Manvantaras and 15 sandhyas. These traditional dates do not extend the 1900–2100 planetary model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .padding(.top, 9)
                }
                .font(.subheadline)
                .tint(TetherTheme.rose)
            }
        }
        .padding(.bottom, 18)
    }
}

private struct SolarLunarDial: View {
    let calendar: HinduCalendar
    let phase: LunarPhase

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.45
            let gold = Color(red: 1, green: 0.81, blue: 0.48)
            func point(_ angle: Double, _ fraction: Double) -> CGPoint {
                let radians = angle * .pi / 180 - .pi / 2
                return CGPoint(x: center.x + cos(radians) * radius * fraction, y: center.y + sin(radians) * radius * fraction)
            }
            for (fraction, color) in [(1.0, gold), (0.78, TetherTheme.mint)] {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * fraction, y: center.y - radius * fraction, width: radius * fraction * 2, height: radius * fraction * 2)), with: .color(color.opacity(0.25)), lineWidth: 1)
            }
            for tick in 0..<30 {
                var line = Path()
                line.move(to: point(Double(tick) * 12, 0.76))
                line.addLine(to: point(Double(tick) * 12, tick % 5 == 0 ? 0.68 : 0.73))
                context.stroke(line, with: .color(TetherTheme.mint.opacity(0.5)), lineWidth: 1)
            }
            for tick in 0..<12 {
                var line = Path()
                line.move(to: point(Double(tick) * 30, 0.95))
                line.addLine(to: point(Double(tick) * 30, 1.04))
                context.stroke(line, with: .color(gold.opacity(0.6)), lineWidth: 1)
            }
            for (angle, fraction, color) in [(calendar.sunTropical, 1.0, gold), (calendar.elongation, 0.78, TetherTheme.mint)] {
                let dot = point(angle, fraction)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(color))
            }
            let moonRadius = radius * 0.46
            let disk = CGRect(x: center.x - moonRadius, y: center.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)
            context.fill(Path(ellipseIn: disk), with: .color(Color(red: 0.09, green: 0.12, blue: 0.20)))
            let direction = phase.waxing ? 1.0 : -1.0
            var lit = Path()
            for index in 0...96 {
                let y = Double(index) / 48 - 1
                let limb = sqrt(max(0, 1 - y * y))
                let p = CGPoint(x: center.x + direction * limb * moonRadius, y: center.y + y * moonRadius)
                if index == 0 { lit.move(to: p) } else { lit.addLine(to: p) }
            }
            for index in (0...96).reversed() {
                let y = Double(index) / 48 - 1
                let limb = sqrt(max(0, 1 - y * y))
                lit.addLine(to: CGPoint(x: center.x - direction * phase.cosPhase * limb * moonRadius, y: center.y + y * moonRadius))
            }
            lit.closeSubpath()
            context.fill(lit, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.62, green: 0.75, blue: 0.88)]), startPoint: CGPoint(x: center.x, y: center.y - moonRadius), endPoint: CGPoint(x: center.x, y: center.y + moonRadius)))
            context.stroke(Path(ellipseIn: disk), with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
    }
}

private struct CycleBand: View {
    let cycle: CosmicCycle
    let progress: Double
    private let colors = [Color(red: 0.91, green: 0.78, blue: 0.51), TetherTheme.rose, TetherTheme.violet, TetherTheme.mint]

    var body: some View {
        Canvas { context, size in
            var x = 0.0
            let segments = CosmicCalendar.segments(for: cycle)
            for segment in segments {
                let width = size.width * segment.duration / cycle.duration
                let color = segments.count == 4 ? colors[segment.id % 4] : segment.isCurrent ? TetherTheme.mint : TetherTheme.violet.opacity(0.42)
                let rectangle = CGRect(x: x, y: 9, width: max(0.2, width - 0.7), height: 12)
                context.fill(Path(roundedRect: rectangle, cornerRadius: 2), with: .color(color))
                x += width
            }
            let marker = max(3, min(size.width - 3, size.width * progress))
            var pointer = Path()
            pointer.move(to: CGPoint(x: marker - 3, y: 0))
            pointer.addLine(to: CGPoint(x: marker + 3, y: 0))
            pointer.addLine(to: CGPoint(x: marker, y: 6))
            pointer.closeSubpath()
            context.fill(pointer, with: .color(.white))
        }
    }
}
