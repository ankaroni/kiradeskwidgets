import SwiftUI
import AppKit
import Combine

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct WidgetHostView: View {
    let kind: WidgetKind
    let m: WidgetManager
    @ObservedObject var store = Store.shared

    var body: some View {
        let base = kind.baseSize
        let scale = store.config(kind).scale
        Group {
            switch kind {
            case .clock: ClockWidget()
            case .bigClock: BigClockWidget()
            case .rings: RingsWidget(stats: m.stats)
            case .analog: AnalogClockWidget()
            case .world: WorldClockWidget()
            case .calendar: CalendarWidget()
            case .agenda: AgendaWidget(m: m.agenda)
            case .weather: WeatherWidget(w: m.weather)
            case .sunmoon: SunMoonWidget(w: m.weather)
            case .system: SystemWidget(stats: m.stats)
            case .diskNet: DiskNetWidget(m: m.netDisk)
            case .nowPlaying: NowPlayingWidget(m: m.nowPlaying)
            case .todo: TodoWidget()
            case .countdown: CountdownWidget()
            case .finance: FinanceWidget(f: m.finance)
            case .pomodoro: PomodoroWidget(p: m.pomodoro)
            case .photo: PhotoWidget()
            case .quote: QuoteWidget()
            case .note: NoteWidget()
            }
        }
        .frame(width: base.width, height: base.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
        .overlay {
            if store.editing {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.white.opacity(0.9))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 13, weight: .bold)).padding(8)
                            .background(Circle().fill(.black.opacity(0.55))).foregroundStyle(.white).padding(10)
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}

@MainActor
final class WidgetManager {
    static let shared = WidgetManager()
    let store = Store.shared
    let weather = WeatherModel()
    let stats = SystemStats()
    let nowPlaying = NowPlayingModel()
    let finance = FinanceModel()
    let netDisk = NetDiskModel()
    let agenda = AgendaModel()
    let pomodoro = PomodoroModel()
    private var windows: [WidgetKind: WidgetWindow] = [:]
    private var testWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var lastCity = ""

    func start() {
        // Test/kısayol: --set <id> ile açılışta bir seti uygula
        if let i = CommandLine.arguments.firstIndex(of: "--set"), i + 1 < CommandLine.arguments.count,
           let set = layoutSets.first(where: { $0.id == CommandLine.arguments[i + 1] }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.apply(set: set) }
        }
        if CommandLine.arguments.contains("--settings-test") {
            DispatchQueue.main.async {
                let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 940, height: 680),
                                 styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                w.title = "HavaliWidget Ayarları (test)"
                w.contentView = NSHostingView(rootView: SettingsView())
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.testWindow = w
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--enable"), i + 1 < CommandLine.arguments.count {
            for name in CommandLine.arguments[i + 1].split(separator: ",") {
                if let k = WidgetKind(rawValue: String(name)) { var c = store.config(k); c.enabled = true; store.s.configs[k.rawValue] = c }
            }
        }
        if CommandLine.arguments.contains("--fake-agenda") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                let now = Date(), cal = Calendar.current
                func ev(_ t: String, _ s: Double, _ d: Double, day: Int = 0, allDay: Bool = false, loc: String? = nil, c: Color) -> AgendaEvent {
                    let base = cal.date(byAdding: .day, value: day, to: now)!
                    let st = allDay ? cal.startOfDay(for: base) : base.addingTimeInterval(s * 60)
                    return AgendaEvent(id: UUID().uuidString, title: t, start: st, end: st.addingTimeInterval(d * 60), allDay: allDay, color: c, location: loc, calendarID: "x")
                }
                self.agenda.access = .granted
                self.agenda.events = [
                    ev("Proje teslimi", 0, 24 * 60, allDay: true, c: .orange),
                    ev("Stand-up toplantısı", -10, 30, c: .blue),
                    ev("Doktor randevusu", 45, 45, loc: "Acıbadem", c: .red),
                    ev("Öğle yemeği · Ayşe", 12 * 60 - Double(cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)) + 24 * 60, 60, day: 0, loc: "Karaköy", c: .green),
                    ev("Uçuş TK 1234", 8 * 60, 120, day: 2, c: .purple),
                ]
            }
        }
        stats.start()
        weather.start(city: store.s.city)
        lastCity = store.s.city
        sync()
        store.$s.debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }.store(in: &bag)
        store.$editing.sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }.store(in: &bag)
        store.$allHidden.sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private func posKey(_ k: WidgetKind) -> String { "pos.\(k.rawValue)" }

    private func savedOrigin(_ k: WidgetKind) -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: posKey(k)) else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? NSPoint(x: p[0], y: p[1]) : nil
    }

    /// Kayıtlı konum yoksa sol üstten başlayıp aşağı dizer, ekran dolunca sağda yeni sütun açar.
    /// (Masaüstü simgeleri varsayılan olarak sağ kenara dizildiği için solu tercih ediyoruz.)
    private func defaultOrigin(_ k: WidgetKind, size: CGSize) -> NSPoint {
        let vf = targetScreen.visibleFrame
        let margin = 24.0, gap = 16.0
        var x = vf.minX + margin
        var y = vf.maxY - margin
        var colWidth = 0.0
        for other in WidgetKind.allCases {
            let c = store.config(other)
            guard c.enabled || other == k else { continue }
            let w = other.baseSize.width * c.scale, h = other.baseSize.height * c.scale
            if y - h < vf.minY + margin && colWidth > 0 {
                x += colWidth + gap
                y = vf.maxY - margin
                colWidth = 0
            }
            if other == k { return NSPoint(x: x, y: y - h) }
            colWidth = max(colWidth, w)
            y -= h + gap
        }
        return NSPoint(x: vf.minX + 40, y: vf.minY + 40)
    }

    private var targetScreen: NSScreen {
        let all = NSScreen.screens
        return all.indices.contains(store.s.screenIndex) ? all[store.s.screenIndex] : (all.first ?? NSScreen.main!)
    }

    private func levelRaw(front: Bool) -> Int {
        Int(CGWindowLevelForKey(.desktopIconWindow)) + (front ? 1 : -1)
    }

    /// Simge arkasında: Finder'ın simge katmanı üstte kalır, tıklamalar widget'a ulaşmaz.
    private func applyBehavior(_ kind: WidgetKind, _ w: WidgetWindow) {
        let front = store.s.placement == .front || store.editing || store.config(kind).clickable
        w.level = NSWindow.Level(rawValue: levelRaw(front: front))
        w.ignoresMouseEvents = store.s.locked && !store.editing ? true : !front
        w.isMovableByWindowBackground = front && (!store.s.locked || store.editing)
    }

    func sync() {
        if store.s.city != lastCity { lastCity = store.s.city; weather.load(city: store.s.city) }
        // Yalnızca açık widget'ların veri kaynaklarını çalıştır (gereksiz ağ/izin yok)
        func on(_ k: WidgetKind) -> Bool { store.config(k).enabled }
        if on(.nowPlaying) { nowPlaying.start() } else { nowPlaying.stop() }
        if on(.finance) { finance.start() } else { finance.stop() }
        if on(.diskNet) { netDisk.start() } else { netDisk.stop() }
        if on(.agenda) { agenda.start() } else { agenda.stop() }
        for kind in WidgetKind.allCases {
            let cfg = store.config(kind)
            guard cfg.enabled else { windows[kind]?.orderOut(nil); windows[kind] = nil; continue }
            if store.allHidden { windows[kind]?.orderOut(nil); if windows[kind] != nil { continue } }
            let size = CGSize(width: kind.baseSize.width * cfg.scale, height: kind.baseSize.height * cfg.scale)
            if let w = windows[kind] {
                if w.frame.size != size {
                    var f = w.frame
                    f.origin.y += f.height - size.height   // sol üst köşe sabit kalsın
                    f.size = size
                    w.setFrame(f, display: true)
                }
                applyBehavior(kind, w)
                if !store.allHidden && !w.isVisible { w.orderFront(nil) }
            } else {
                let w = WidgetWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                     backing: .buffered, defer: false)
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                w.isOpaque = false
                w.backgroundColor = .clear
                w.hasShadow = false
                w.isReleasedWhenClosed = false
                applyBehavior(kind, w)
                let host = NSHostingView(rootView: WidgetHostView(kind: kind, m: self))
                host.frame = NSRect(origin: .zero, size: size)
                w.contentView = host
                w.setFrameOrigin(savedOrigin(kind) ?? defaultOrigin(kind, size: size))
                w.orderFront(nil)
                NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self, weak w] _ in
                    guard let self, let w else { return }
                    let o = w.frame.origin
                    UserDefaults.standard.set("\(o.x),\(o.y)", forKey: self.posKey(kind))
                }
                windows[kind] = w
            }
        }
    }

    /// Hazır seti uygular: widget'ları seçer, stil/renk ayarlar, ekrana sığacak şekilde ölçekleyip dizer
    func apply(set: LayoutSet) {
        let vf = targetScreen.visibleFrame
        let plan = AutoLayout.plan(set.columns, in: vf)
        for k in WidgetKind.allCases { var c = store.config(k); c.enabled = false; store.s.configs[k.rawValue] = c }
        for it in set.items {
            var c = store.config(it.kind)
            c.enabled = true; c.style = it.style; c.scale = it.scale * plan.fit; c.opacity = 1
            store.s.configs[it.kind.rawValue] = c
        }
        store.s.accentHue = set.hue
        for (k, r) in plan.frames { UserDefaults.standard.set("\(r.origin.x),\(r.origin.y)", forKey: posKey(k)) }
        sync()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            for (k, w) in self.windows { if let o = self.savedOrigin(k) { w.setFrameOrigin(o) } }
        }
    }

    /// Açık widget'ları düzenli sütunlara dizer (boyutlarını değiştirmez, sığmazsa küçültür)
    func autoArrangeCurrent() {
        let vf = targetScreen.visibleFrame
        let kinds = WidgetKind.allCases.filter { store.config($0).enabled }.map { ($0, store.config($0).scale) }
        guard !kinds.isEmpty else { return }
        let cols = AutoLayout.autoColumns(kinds, in: vf)
        let plan = AutoLayout.plan(cols, in: vf, boost: false)
        if plan.fit < 1 {
            for (k, _) in kinds { var c = store.config(k); c.scale *= plan.fit; store.s.configs[k.rawValue] = c }
        }
        for (k, r) in plan.frames { UserDefaults.standard.set("\(r.origin.x),\(r.origin.y)", forKey: posKey(k)) }
        sync()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            for (k, w) in self.windows { if let o = self.savedOrigin(k) { w.setFrameOrigin(o) } }
        }
    }

    func resetPositions() {
        for k in WidgetKind.allCases { UserDefaults.standard.removeObject(forKey: posKey(k)) }
        for (k, w) in windows { w.setFrameOrigin(defaultOrigin(k, size: w.frame.size)) }
    }
}
