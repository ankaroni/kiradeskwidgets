import SwiftUI

// MARK: - Ortak kart görünümü

/// Doku: kartların düz görünmesini engelleyen çok ince, sabit gren
struct Grain: View {
    var amount: Double = 0.05
    var body: some View {
        Canvas { g, size in
            for i in 0..<420 {
                func r(_ k: Int) -> Double { let x = sin(Double(i &* 127 &+ k &* 311)) * 43758.5453; return x - floor(x) }
                let p = CGRect(x: r(1) * size.width, y: r(2) * size.height, width: 1.4, height: 1.4)
                g.fill(Path(ellipseIn: p), with: .color((r(3) > 0.5 ? Color.white : Color.black).opacity(amount)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Kartın zemini: Card, set önizlemeleri ve stil örnekleri aynı çizimi kullanır
struct CardBackground: View {
    let style: CardStyle
    var radius: CGFloat = 32
    var grain = true
    var hueOverride: Double? = nil
    @ObservedObject private var store = Store.shared

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// Kenarda çerçeve yerine yumuşak ışık: üstte parlama, altta hafif gölge
    private func light(_ top: Double, _ bottom: Double) -> some View {
        shape.strokeBorder(LinearGradient(colors: [.white.opacity(top), .clear, .black.opacity(bottom)],
                                          startPoint: .top, endPoint: .bottom), lineWidth: max(0.6, radius / 24))
    }

    private func g(_ a: Double) -> some View { grain ? AnyView(Grain(amount: a).clipShape(shape)) : AnyView(EmptyView()) }

    var body: some View {
        let hue = hueOverride ?? store.s.accentHue
        switch style {
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.20), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))))
                .overlay(g(0.03))
                .overlay(light(0.35, 0.18))
        case .dark:
            shape.fill(LinearGradient(colors: [Color(white: 0.13).opacity(0.90), Color(white: 0.02).opacity(0.84)], startPoint: .top, endPoint: .bottom))
                .overlay(g(0.05))
                .overlay(light(0.16, 0.0))
        case .aurora:
            shape.fill(.ultraThinMaterial)
                .overlay(
                    ZStack {
                        RadialGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 1).opacity(0.75), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: radius * 9)
                        RadialGradient(colors: [Color(hue: hue + 0.28, saturation: 0.65, brightness: 1).opacity(0.65), .clear],
                                       center: .bottomTrailing, startRadius: 0, endRadius: radius * 9)
                        RadialGradient(colors: [Color(hue: hue + 0.55, saturation: 0.6, brightness: 1).opacity(0.32), .clear],
                                       center: UnitPoint(x: 0.9, y: 0.08), startRadius: 0, endRadius: radius * 5)
                    }
                    .clipShape(shape)
                )
                .overlay(g(0.04))
                .overlay(light(0.30, 0.10))
        case .neon:
            let neon = Color(hue: hue, saturation: 0.75, brightness: 1)
            shape.fill(Color.black.opacity(0.66))
                .overlay(shape.fill(RadialGradient(colors: [neon.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: radius * 7.5)))
                .overlay(g(0.05))
                .overlay(shape.inset(by: 1.5).strokeBorder(neon, lineWidth: max(1, radius / 16)).shadow(color: neon, radius: radius / 5))
        case .matte:
            shape.fill(Color(hue: hue, saturation: 0.16, brightness: 0.97))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .center)))
                .overlay(g(0.035))
        case .frost:
            shape.fill(.regularMaterial)
                .overlay(shape.fill(Color.white.opacity(0.80)))
                .overlay(g(0.03))
                .overlay(light(0.6, 0.06))
        case .gradient:
            shape.fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.78, brightness: 0.98),
                                               Color(hue: hue + 0.14, saturation: 0.85, brightness: 0.78)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: radius * 5.5)))
                .overlay(g(0.045))
        case .clear:
            Color.clear
        }
    }
}

struct Card<Content: View>: View {
    let style: CardStyle
    var opacity: Double = 1.0
    var underlay: AnyView? = nil
    @ViewBuilder var content: Content

    private var radius: CGFloat {
        switch style { case .matte: 44; case .gradient: 38; case .frost: 40; default: 32 }
    }

    var body: some View {
        let ink = inkColor(style)
        content
            .foregroundStyle(ink)
            .shadow(color: .black.opacity(style == .clear ? 0.6 : 0), radius: style == .clear ? 6 : 0, y: 1)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    CardBackground(style: style, radius: radius).opacity(opacity)
                    if let u = underlay { Color.clear.overlay { u }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)).allowsHitTesting(false) }
                }
            }
    }
}

private let trLocale = Locale(identifier: "tr_TR")

private func fmt(_ date: Date, _ format: String) -> String {
    let f = DateFormatter(); f.locale = trLocale; f.dateFormat = format
    return f.string(from: date)
}

// MARK: - Saat

struct ClockWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.clock)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: store.s.showSeconds ? 1 : 10)) { ctx in
            Card(style: cfg.style, opacity: cfg.opacity) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(fmt(ctx.date, store.s.clock24h ? "HH:mm" : "h:mm"))
                            .font(.system(size: 80, weight: .ultraLight, design: .rounded)).monospacedDigit()
                            .foregroundStyle(LinearGradient(colors: [ink, store.accent(on: cfg.style).opacity(0.9)], startPoint: .top, endPoint: .bottom))
                        if store.s.showSeconds {
                            Text(fmt(ctx.date, "ss")).font(.system(size: 26, weight: .light, design: .rounded))
                                .foregroundStyle(store.accent(on: cfg.style)).monospacedDigit()
                        } else if !store.s.clock24h {
                            Text(fmt(ctx.date, "a")).font(.system(size: 22, weight: .light, design: .rounded))
                                .foregroundStyle(store.accent(on: cfg.style))
                        }
                    }
                    .minimumScaleFactor(0.6).lineLimit(1)
                    Text(fmt(ctx.date, "EEEE, d MMMM").capitalized)
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .foregroundStyle(ink.opacity(0.85))
                }
            }
        }
    }
}

// MARK: - Takvim

struct CalendarWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.calendar)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Card(style: cfg.style, opacity: cfg.opacity) {
                let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.locale = trLocale; return c }()
                let first = cal.date(from: cal.dateComponents([.year, .month], from: ctx.date))!
                let days = cal.range(of: .day, in: .month, for: first)!.count
                let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
                let today = cal.component(.day, from: ctx.date)
                VStack(alignment: .leading, spacing: 10) {
                    Text(fmt(ctx.date, "LLLL yyyy").capitalized)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"], id: \.self) {
                            Text($0).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.opacity(0.5))
                        }
                        ForEach(0..<(offset + days), id: \.self) { i in
                            if i < offset { Color.clear.frame(height: 26) }
                            else {
                                let d = i - offset + 1
                                Text("\(d)").font(.system(size: 14, weight: d == today ? .bold : .regular, design: .rounded))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(d == today ? store.accent(on: cfg.style).opacity(0.9) : .clear))
                                    .foregroundStyle(d == today ? Color.black : ink.opacity(0.9))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Hava durumu

struct WeatherWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var w: WeatherModel
    var body: some View {
        let cfg = store.config(.weather)
        let ink = inkColor(cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity) {
            if let e = w.error, !w.loaded {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Hava durumu", systemImage: "cloud.sun").font(.headline)
                    Text(e).foregroundStyle(ink.opacity(0.7))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.city).font(.system(size: 17, weight: .medium, design: .rounded))
                            Text(WeatherModel.text(w.code)).font(.system(size: 13)).foregroundStyle(ink.opacity(0.7))
                            Text("\(Int(w.temp.rounded()))°").font(.system(size: 50, weight: .thin, design: .rounded))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Image(systemName: WeatherModel.symbol(w.code)).symbolRenderingMode(.multicolor)
                                .font(.system(size: 34))
                            Text("Hissedilen \(Int(w.feels.rounded()))°").font(.system(size: 11)).foregroundStyle(ink.opacity(0.7))
                            Text("Rüzgâr \(Int(w.wind.rounded())) km/s").font(.system(size: 11)).foregroundStyle(ink.opacity(0.7))
                        }
                    }
                    Sparkline(values: w.hourly, color: store.accent(on: cfg.style), ink: ink).frame(height: 46)
                    HStack {
                        ForEach(w.days) { d in
                            VStack(spacing: 3) {
                                Text(d.label.capitalized).font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                                Image(systemName: WeatherModel.symbol(d.code)).symbolRenderingMode(.multicolor).font(.system(size: 16))
                                Text("\(Int(d.max.rounded()))° / \(Int(d.min.rounded()))°").font(.system(size: 11, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sistem

struct Ring: View {
    let value: Double
    let title: String
    let text: String
    let color: Color
    var ink: Color = .white
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(ink.opacity(0.15), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.001, min(1, value)))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 62, height: 62)
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }
}

struct SystemWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var stats: SystemStats
    var body: some View {
        let cfg = store.config(.system)
        let ink = inkColor(cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity) {
            HStack {
                Ring(value: stats.cpu, title: "CPU", text: "\(Int(stats.cpu * 100))%", color: store.accent(on: cfg.style), ink: ink)
                Ring(value: stats.ram, title: "RAM", text: "\(Int(stats.ram * 100))%", color: Color(hue: store.s.accentHue + 0.2, saturation: 0.5, brightness: 1), ink: ink)
                if stats.battery >= 0 {
                    Ring(value: stats.battery, title: stats.charging ? "Şarj" : "Pil", text: "\(Int(stats.battery * 100))%",
                         color: stats.battery < 0.2 ? .red : Color(hue: 0.33, saturation: 0.55, brightness: 1), ink: ink)
                }
            }
        }
    }
}

// MARK: - Not

struct NoteWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.note)
        let ink = inkColor(cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Not", systemImage: "note.text").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.accent(on: cfg.style))
                Text(store.s.noteText).font(.system(size: 17, weight: .regular, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
