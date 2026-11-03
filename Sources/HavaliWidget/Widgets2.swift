import SwiftUI

private let tr = Locale(identifier: "tr_TR")
private func fmt(_ date: Date, _ format: String, tz: TimeZone? = nil) -> String {
    let f = DateFormatter(); f.locale = tr; f.dateFormat = format
    if let tz { f.timeZone = tz }
    return f.string(from: date)
}

// MARK: - Analog saat

struct AnalogClockWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.analog)
        let ink = inkColor(cfg.style)
        let withSec = store.s.analogSeconds
        TimelineView(.periodic(from: .now, by: withSec ? 1 : 15)) { ctx in
            Card(style: cfg.style, opacity: cfg.opacity) {
                Canvas { g, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) / 2 - 2
                    let cal = Calendar.current
                    let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: ctx.date)
                    let sec = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1e9
                    let min = Double(comps.minute ?? 0) + sec / 60
                    let hr = Double((comps.hour ?? 0) % 12) + min / 60

                    for i in 0..<60 {
                        let a = Double(i) / 60 * 2 * .pi
                        let long = i % 5 == 0
                        let r1 = r * (long ? 0.86 : 0.92), r2 = r * 0.97
                        var p = Path()
                        p.move(to: CGPoint(x: c.x + sin(a) * r1, y: c.y - cos(a) * r1))
                        p.addLine(to: CGPoint(x: c.x + sin(a) * r2, y: c.y - cos(a) * r2))
                        g.stroke(p, with: .color(ink.opacity(long ? 0.9 : 0.35)), lineWidth: long ? 2.2 : 1)
                    }
                    func hand(_ angle: Double, _ len: Double, _ w: Double, _ color: Color) {
                        var p = Path()
                        p.move(to: c)
                        p.addLine(to: CGPoint(x: c.x + sin(angle) * r * len, y: c.y - cos(angle) * r * len))
                        g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
                    }
                    hand(hr / 12 * 2 * .pi, 0.5, 5, .white)
                    hand(min / 60 * 2 * .pi, 0.76, 3.5, .white)
                    if withSec { hand(sec / 60 * 2 * .pi, 0.86, 1.6, store.accent(on: cfg.style)) }
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(store.accent(on: cfg.style)))
                }
            }
        }
    }
}

// MARK: - Dünya saati

struct WorldClockWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.world)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            Card(style: cfg.style, opacity: cfg.opacity) {
                VStack(spacing: 0) {
                    ForEach(Array(store.s.worldZones.prefix(4).enumerated()), id: \.offset) { i, id in
                        if let tz = TimeZone(identifier: id) {
                            let name = worldCities.first { $0.tz == id }?.name ?? id
                            let diff = (tz.secondsFromGMT(for: ctx.date) - TimeZone.current.secondsFromGMT(for: ctx.date)) / 3600
                            let sameDay = fmt(ctx.date, "d", tz: tz) == fmt(ctx.date, "d")
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(name).font(.system(size: 16, weight: .medium, design: .rounded))
                                    Text(sameDay ? "Bugün" : (diff > 0 ? "Yarın" : "Dün") + (diff == 0 ? "" : ", \(diff > 0 ? "+" : "")\(diff) sa"))
                                        .font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
                                }
                                Spacer()
                                Text(fmt(ctx.date, "HH:mm", tz: tz))
                                    .font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit()
                            }
                            .padding(.vertical, 5)
                            if i < min(4, store.s.worldZones.count) - 1 { Divider().overlay(ink.opacity(0.12)) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Ajanda

struct AgendaWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var m: AgendaModel

    private func dayLabel(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "BUGÜN" }
        if cal.isDate(d, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now)!) { return "YARIN" }
        return fmt(d, "EEE d MMM").uppercased()
    }

    private func badge(_ e: AgendaEvent, now: Date) -> (String, Bool)? {
        if e.allDay { return nil }
        if e.start <= now && e.end > now { return ("Şimdi", true) }
        let mins = Int(e.start.timeIntervalSince(now) / 60)
        if mins > 0 && mins <= 90 { return (mins >= 60 ? "\(mins / 60) sa \(mins % 60) dk" : "\(mins) dk", false) }
        return nil
    }

    var body: some View {
        let cfg = store.config(.agenda)
        let ink = inkColor(cfg.style)
        let acc = store.accent(on: cfg.style)
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            Card(style: cfg.style, opacity: cfg.opacity) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("Ajanda", systemImage: "calendar").font(.system(size: 13, weight: .semibold)).foregroundStyle(acc)
                        Spacer()
                        if m.access == .granted {
                            Text("\(store.s.agendaDays) gün").font(.system(size: 11)).foregroundStyle(ink.opacity(0.5))
                        }
                    }
                    switch m.access {
                    case .granted:
                        if m.events.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Önümüzdeki \(store.s.agendaDays) gün boş 🎉").font(.system(size: 15, design: .rounded))
                                Text("Takvimde etkinlik yok ya da seçili takvimler gizli.").font(.system(size: 11)).foregroundStyle(ink.opacity(0.55))
                            }
                        } else {
                            eventList(now: now, ink: ink, acc: acc)
                        }
                    case .denied:
                        Text("Takvim erişimi kapalı.").font(.system(size: 14, weight: .medium))
                        Text("Etkinlikleri göstermek için izin gerekli.").font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
                        HStack {
                            Button("Ayarları aç") { m.openSettings() }
                            Button("Tekrar dene") { m.requestAccess() }
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(acc).buttonStyle(.plain)
                    default:
                        Text("Takvim izni isteniyor…").font(.system(size: 14, weight: .medium))
                        Button("İzin ver") { m.requestAccess() }.font(.system(size: 12, weight: .medium)).foregroundStyle(acc).buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func eventList(now: Date, ink: Color, acc: Color) -> some View {
        let cal = Calendar.current
        let groups = Dictionary(grouping: m.events) { cal.startOfDay(for: max($0.start, cal.startOfDay(for: now))) }
        let days = groups.keys.sorted()
        // En fazla 6 satır göster (başlıklar dahil)
        let rows: [(Date?, AgendaEvent?)] = days.flatMap { d -> [(Date?, AgendaEvent?)] in
            [(d, nil)] + (groups[d] ?? []).map { (nil, $0) }
        }.prefix(8).map { $0 }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let d = row.0 {
                    Text(dayLabel(d, now: now)).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(ink.opacity(0.5)).padding(.top, 2)
                } else if let e = row.1 {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            Text(sub(e)).font(.system(size: 11)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let (t, live) = badge(e, now: now) {
                            Text(t).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(live ? acc : ink.opacity(0.15)))
                                .foregroundStyle(live ? (inkColor(store.config(.agenda).style) == .white ? Color.black : .white) : ink)
                        }
                    }
                }
            }
        }
    }

    private func sub(_ e: AgendaEvent) -> String {
        var parts: [String] = []
        parts.append(e.allDay ? "Tüm gün" : "\(fmt(e.start, "HH:mm"))–\(fmt(e.end, "HH:mm"))")
        if let l = e.location { parts.append(l) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Güneş ve ay

struct SunMoonWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var w: WeatherModel
    var body: some View {
        let cfg = store.config(.sunmoon)
        let ink = inkColor(cfg.style)
        let moon = MoonInfo.at(Date())
        Card(style: cfg.style, opacity: cfg.opacity) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(w.sunrise.isEmpty ? "—" : "Doğuş  \(w.sunrise)", systemImage: "sunrise.fill")
                        .symbolRenderingMode(.multicolor).font(.system(size: 15, design: .rounded))
                    Label(w.sunset.isEmpty ? "—" : "Batış  \(w.sunset)", systemImage: "sunset.fill")
                        .symbolRenderingMode(.multicolor).font(.system(size: 15, design: .rounded))
                    if let len = w.dayLength { Text("Gün uzunluğu \(len)").font(.system(size: 11)).foregroundStyle(ink.opacity(0.6)) }
                }
                Spacer()
                VStack(spacing: 4) {
                    Text(moon.symbol).font(.system(size: 44))
                    Text(moon.name).font(.system(size: 12, weight: .medium))
                    Text("%\(Int(moon.illumination * 100)) aydınlık").font(.system(size: 11)).foregroundStyle(ink.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Disk ve ağ

struct DiskNetWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var m: NetDiskModel
    var body: some View {
        let cfg = store.config(.diskNet)
        let ink = inkColor(cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity) {
            HStack(spacing: 18) {
                Ring(value: m.diskUsed, title: m.diskFreeText, text: "\(Int(m.diskUsed * 100))%", color: Color(hue: 0.08, saturation: 0.6, brightness: 1), ink: ink)
                VStack(alignment: .leading, spacing: 10) {
                    Label(NetDiskModel.speed(m.down), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(store.accent(on: cfg.style))
                    Label(NetDiskModel.speed(m.up), systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color(hue: store.s.accentHue + 0.25, saturation: 0.5, brightness: 1))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Müzik çalar

struct SeekBar: View {
    let fraction: Double
    let tint: Color
    let ink: Color
    let onSeek: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.22))
                Capsule().fill(tint).frame(width: max(5, g.size.width * min(max(fraction, 0), 1)))
            }
            .frame(height: 5).frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in onSeek(v.location.x / max(1, g.size.width)) })
        }
        .frame(height: 14)
    }
}

struct NowPlayingWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var m: NowPlayingModel

    private func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    var body: some View {
        let cfg = store.config(.nowPlaying)
        let ink = inkColor(cfg.style)
        let tint = m.available ? m.tint : store.accent(on: cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity, underlay: underlay(ink)) {
            if m.available { player(ink, tint, cfg) } else { idle(ink, tint) }
        }
    }

    /// Kapak resminden bulanık, renkli bir parıltı (kart tüm yüzeyiyle müziğin rengine bürünür)
    private func underlay(_ ink: Color) -> AnyView? {
        guard m.available, let img = m.artwork else { return nil }
        return AnyView(
            ZStack {
                Image(nsImage: img).resizable().scaledToFill().blur(radius: 38).opacity(0.5).scaleEffect(1.4)
                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            }
        )
    }

    private func player(_ ink: Color, _ tint: Color, _ cfg: WidgetConfig) -> some View {
        HStack(spacing: 16) {
            Group {
                if let a = m.artwork {
                    Image(nsImage: a).resizable().scaledToFill()
                } else {
                    ZStack { ink.opacity(0.12); Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(ink.opacity(0.6)) }
                }
            }
            .frame(width: 118, height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: m.playing ? "waveform" : "pause.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    Text(m.displayName.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(1.2).foregroundStyle(ink.opacity(0.55))
                }
                Text(m.title).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                Text(m.artist).font(.system(size: 13)).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                Spacer(minLength: 2)
                TimelineView(.periodic(from: .now, by: m.playing ? 1 : 3600)) { ctx in
                    let pos = m.position(at: ctx.date)
                    VStack(spacing: 1) {
                        SeekBar(fraction: m.duration > 0 ? pos / m.duration : 0, tint: tint, ink: ink) { m.seek(fraction: $0) }
                        HStack {
                            Text(clock(pos)); Spacer(); Text(m.duration > 0 ? "-" + clock(max(0, m.duration - pos)) : "")
                        }
                        .font(.system(size: 9.5, weight: .medium)).monospacedDigit().foregroundStyle(ink.opacity(0.5))
                    }
                }
                HStack(spacing: 22) {
                    Spacer()
                    Button { m.command("previous track") } label: { Image(systemName: "backward.fill").font(.system(size: 16)) }
                    Button { m.command("playpause") } label: {
                        Image(systemName: m.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34)).foregroundStyle(tint)
                    }
                    Button { m.command("next track") } label: { Image(systemName: "forward.fill").font(.system(size: 16)) }
                    Spacer()
                }
                .buttonStyle(.plain).foregroundStyle(ink)
                if let n = m.note {
                    Text(n).font(.system(size: 9.5)).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
    }

    private func idle(_ ink: Color, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note.list").font(.system(size: 24)).foregroundStyle(tint)
                Spacer()
                Button { m.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(ink.opacity(0.6))
            }
            Text("Şu an müzik çalmıyor").font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Spotify veya Müzik'te bir parça başlatın, burada otomatik görünür. Zaten çalıyorsa yenile düğmesine basın.")
                .font(.system(size: 12)).foregroundStyle(ink.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            if let n = m.note { Text(n).font(.system(size: 10)).foregroundStyle(.orange) }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Yapılacaklar

struct TodoWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.todo)
        let ink = inkColor(cfg.style)
        let done = store.s.todos.filter(\.done).count
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Yapılacaklar", systemImage: "checklist").font(.system(size: 13, weight: .semibold)).foregroundStyle(store.accent(on: cfg.style))
                    Spacer()
                    Text("\(done)/\(store.s.todos.count)").font(.system(size: 12)).foregroundStyle(ink.opacity(0.6)).monospacedDigit()
                }
                ForEach(store.s.todos.prefix(7)) { t in
                    Button {
                        if let i = store.s.todos.firstIndex(where: { $0.id == t.id }) { store.s.todos[i].done.toggle() }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(t.done ? store.accent(on: cfg.style) : ink.opacity(0.6))
                            Text(t.text).font(.system(size: 14, design: .rounded)).lineLimit(1)
                                .strikethrough(t.done).foregroundStyle(ink.opacity(t.done ? 0.45 : 1))
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Geri sayım

struct CountdownWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.countdown)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: ctx.date),
                                                       to: Calendar.current.startOfDay(for: store.s.countdownDate)).day ?? 0
            Card(style: cfg.style, opacity: cfg.opacity) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(store.s.countdownTitle, systemImage: "hourglass").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(store.accent(on: cfg.style))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(abs(days))").font(.system(size: 68, weight: .ultraLight, design: .rounded)).monospacedDigit()
                            .foregroundStyle(LinearGradient(colors: [.white, store.accent(on: cfg.style)], startPoint: .top, endPoint: .bottom))
                        Text(days >= 0 ? "gün kaldı" : "gün önce").font(.system(size: 16, design: .rounded)).foregroundStyle(ink.opacity(0.75))
                    }
                    Text(fmt(store.s.countdownDate, "d MMMM yyyy, EEEE")).font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Döviz ve kripto

struct FinanceWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var f: FinanceModel
    private func tl(_ v: Double) -> String { v == 0 ? "—" : String(format: "%.2f ₺", v).replacingOccurrences(of: ".", with: ",") }
    private func usd(_ v: Double) -> String { v == 0 ? "—" : "$" + (NumberFormatter.localizedString(from: NSNumber(value: v.rounded()), number: .decimal)) }
    var body: some View {
        let cfg = store.config(.finance)
        let ink = inkColor(cfg.style)
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(spacing: 7) {
                row("🇺🇸  Dolar", tl(f.usd), nil)
                row("🇪🇺  Euro", tl(f.eur), nil)
                row("🇬🇧  Sterlin", tl(f.gbp), nil)
                if store.s.showCrypto {
                    Divider().overlay(ink.opacity(0.15))
                    row("₿  Bitcoin", usd(f.btc), f.btcChange)
                    row("Ξ  Ethereum", usd(f.eth), f.ethChange)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func row(_ name: String, _ value: String, _ change: Double?) -> some View {
        HStack {
            Text(name).font(.system(size: 14, design: .rounded))
            Spacer()
            if let c = change {
                Text(String(format: "%+.1f%%", c)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(c >= 0 ? Color.green : Color.red)
            }
            Text(value).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

// MARK: - Pomodoro

struct PomodoroWidget: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var p: PomodoroModel
    var body: some View {
        let cfg = store.config(.pomodoro)
        let ink = inkColor(cfg.style)
        let focus = store.s.pomodoroFocus, rest = store.s.pomodoroBreak
        let total = Double((p.focusMode ? focus : rest) * 60)
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ink.opacity(0.15), lineWidth: 8)
                    Circle().trim(from: 0, to: max(0.001, Double(p.remaining) / max(1, total)))
                        .stroke(p.focusMode ? store.accent(on: cfg.style) : Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(String(format: "%02d:%02d", p.remaining / 60, p.remaining % 60))
                            .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                        Text(p.focusMode ? "Odak" : "Mola").font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
                    }
                }
                .frame(width: 112, height: 112)
                HStack(spacing: 18) {
                    Button { p.toggle(focus: focus, rest: rest) } label: { Image(systemName: p.running ? "pause.fill" : "play.fill") }
                    Button { p.reset(focus: focus, rest: rest) } label: { Image(systemName: "arrow.counterclockwise") }
                    Button { p.switchMode(focus: focus, rest: rest) } label: { Image(systemName: "arrow.left.arrow.right") }
                    Text("🍅 \(p.completed)").font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
                .buttonStyle(.plain).font(.system(size: 17)).foregroundStyle(store.accent(on: cfg.style))
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { p.configure(focus: focus, rest: rest) }
    }
}

// MARK: - Fotoğraf çerçevesi

struct PhotoWidget: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let cfg = store.config(.photo)
        let ink = inkColor(cfg.style)
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let files = PhotoFrame.files
            ZStack {
                if files.isEmpty {
                    Card(style: cfg.style, opacity: cfg.opacity) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 30))
                            Text("Ayarlardan fotoğraf seçin").font(.system(size: 13)).foregroundStyle(ink.opacity(0.7))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    let idx = Int(ctx.date.timeIntervalSince1970 / max(3, store.s.photoInterval)) % files.count
                    if let cg = PhotoCache.shared.image(files[idx]) {
                        Image(decorative: cg, scale: 1).resizable().scaledToFill()
                            .frame(width: 300, height: 240).clipped()
                            .id(idx).transition(.opacity)
                    }
                }
            }
            .frame(width: 300, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(ink.opacity(0.18), lineWidth: 1))
            .animation(.easeInOut(duration: 0.8), value: Int(ctx.date.timeIntervalSince1970 / max(3, store.s.photoInterval)))
        }
    }
}

// MARK: - Günün sözü

struct QuoteWidget: View {
    @ObservedObject var store = Store.shared
    @State private var offset = 0
    var body: some View {
        let cfg = store.config(.quote)
        let ink = inkColor(cfg.style)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let q = dailyQuotes[(day + offset) % dailyQuotes.count]
        Card(style: cfg.style, opacity: cfg.opacity) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "quote.opening").foregroundStyle(store.accent(on: cfg.style)).font(.system(size: 16))
                Text(q.0).font(.system(size: 17, weight: .regular, design: .serif)).italic().fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("— \(q.1)").font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { offset += 1 }
    }
}
