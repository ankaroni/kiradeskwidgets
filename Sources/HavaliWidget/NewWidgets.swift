import SwiftUI

private let trL = Locale(identifier: "tr_TR")
private func fmtD(_ date: Date, _ format: String) -> String {
    let f = DateFormatter(); f.locale = trL; f.dateFormat = format
    return f.string(from: date)
}

// MARK: - Saatlik sıcaklık grafiği

struct Sparkline: View {
    let values: [Double]
    let color: Color
    let ink: Color
    var body: some View {
        Canvas { g, size in
            guard values.count > 2, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, 1)
            let pad = 6.0
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: Double(i) / Double(values.count - 1) * size.width,
                        y: pad + (1 - (v - lo) / span) * (size.height - 2 * pad))
            }
            // Yumuşak eğri (Catmull-Rom benzeri)
            var line = Path()
            line.move(to: pts[0])
            for i in 1..<pts.count {
                let p0 = pts[max(i - 2, 0)], p1 = pts[i - 1], p2 = pts[i], p3 = pts[min(i + 1, pts.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                line.addCurve(to: p2, control1: c1, control2: c2)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            g.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            g.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            if let imax = values.firstIndex(of: hi), let imin = values.firstIndex(of: lo) {
                for (i, v) in [(imax, hi), (imin, lo)] {
                    g.fill(Path(ellipseIn: CGRect(x: pts[i].x - 3, y: pts[i].y - 3, width: 6, height: 6)), with: .color(ink))
                    g.draw(Text("\(Int(v.rounded()))°").font(.system(size: 9, weight: .semibold)).foregroundColor(ink.opacity(0.8)),
                           at: CGPoint(x: pts[i].x, y: pts[i].y + (i == imax ? -9 : 10)))
                }
            }
        }
    }
}

// MARK: - Dev dikey saat

struct BigClockWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.bigClock)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: 10)) { ctx in
            Card(style: cfg.style, opacity: cfg.opacity) {
                VStack(alignment: .leading, spacing: -22) {
                    Text(fmtD(ctx.date, store.s.clock24h ? "HH" : "hh"))
                        .font(.system(size: 158, weight: .ultraLight, design: .rounded)).monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [ink, store.accent(on: cfg.style)], startPoint: .top, endPoint: .bottom))
                    Text(fmtD(ctx.date, "mm"))
                        .font(.system(size: 158, weight: .ultraLight, design: .rounded)).monospacedDigit()
                        .foregroundStyle(ink.opacity(0.92))
                    HStack(spacing: 8) {
                        Capsule().fill(store.accent(on: cfg.style)).frame(width: 26, height: 4)
                        Text(fmtD(ctx.date, "EEEE d MMMM").uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.6)
                            .foregroundStyle(ink.opacity(0.7))
                    }
                    .padding(.top, 24)
                }
                .minimumScaleFactor(0.5)
            }
        }
    }
}

// MARK: - İç içe halkalar (Apple Watch tarzı)

struct RingsWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var stats: SystemStats
    var body: some View {
        let cfg = store.config(.rings)
        let ink = inkColor(cfg.style)
        let c1 = store.accent(on: cfg.style)
        let c2 = Color(hue: store.s.accentHue + 0.2, saturation: 0.6, brightness: 1)
        let c3 = Color(hue: store.s.accentHue + 0.42, saturation: 0.6, brightness: 1)
        let third = stats.battery >= 0 ? stats.battery : 0
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(spacing: 14) {
                ZStack {
                    ring(190, stats.cpu, c1, ink)
                    ring(150, stats.ram, c2, ink)
                    ring(110, third, c3, ink)
                }
                .frame(width: 190, height: 190)
                HStack(spacing: 14) {
                    legend("CPU", Int(stats.cpu * 100), c1, ink)
                    legend("RAM", Int(stats.ram * 100), c2, ink)
                    legend(stats.battery >= 0 ? "Pil" : "—", Int(third * 100), c3, ink)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private func ring(_ d: CGFloat, _ v: Double, _ c: Color, _ ink: Color) -> some View {
        ZStack {
            Circle().stroke(c.opacity(0.22), lineWidth: 15)
            Circle().trim(from: 0, to: max(0.012, min(1, v)))
                .stroke(c, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: c.opacity(0.5), radius: 5)
        }
        .frame(width: d, height: d)
    }
    private func legend(_ t: String, _ v: Int, _ c: Color, _ ink: Color) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.65)) }
            Text("%\(v)").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
