import SwiftUI
import AppKit
import EventKit
import Darwin
import ImageIO

// MARK: - Tanı günlüğü (izin ve veri sorunlarını anlamak için)

enum HWLog {
    static func write(_ line: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HavaliWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("durum.log")
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: f, atomically: true, encoding: .utf8) }
    }
}

// MARK: - Müzik (Spotify / Apple Music)
//
// Çalan parça, Spotify ve Müzik'in yayınladığı sistem bildirimlerinden okunur: izin gerekmez, sürekli sorgulama yok.
// Yalnızca düğmeler (oynat/duraklat/ileri/geri/ilerleme) AppleScript kullanır ve otomasyon izni ister.

@MainActor
final class NowPlayingModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var app = ""                 // "Spotify" veya "Music"
    @Published var playing = false
    @Published var available = false
    @Published var artwork: NSImage?
    @Published var tint: Color = .white
    @Published var duration = 0.0           // saniye
    @Published var note: String?            // kullanıcıya ipucu / izin uyarısı

    private var basePos = 0.0
    private var baseDate = Date()
    private var trackKey = ""
    private var tokens: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "havaliwidget.applescript")

    var displayName: String { app == "Music" ? "Müzik" : app }

    func position(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let p = playing ? basePos + date.timeIntervalSince(baseDate) : basePos
        return min(max(p, 0), duration)
    }

    func start() {
        guard tokens.isEmpty else { return }
        let c = DistributedNotificationCenter.default()
        tokens.append(c.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo as? [String: Any] ?? [:]
            Task { @MainActor in self?.handle(info, app: "Spotify") }
        })
        for name in ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo"] {
            tokens.append(c.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] n in
                let info = n.userInfo as? [String: Any] ?? [:]
                Task { @MainActor in self?.handle(info, app: "Music") }
            })
        }
        // Uygulama kapanırsa widget boşalsın
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard let self else { return }
                if (app.bundleIdentifier == "com.spotify.client" && self.app == "Spotify") ||
                   (app.bundleIdentifier == "com.apple.Music" && self.app == "Music") { self.clear() }
            }
        })
        refresh()
    }

    func stop() {
        for t in tokens { DistributedNotificationCenter.default().removeObserver(t); NSWorkspace.shared.notificationCenter.removeObserver(t) }
        tokens = []
    }

    private func clear() {
        available = false; playing = false; title = ""; artist = ""; album = ""; artwork = nil; trackKey = ""
    }

    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    private func handle(_ info: [String: Any], app: String) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" || state.isEmpty { if self.app == app { clear() }; return }
        let name = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let dur = app == "Spotify" ? (num(info["Duration"]) ?? 0) / 1000 : (num(info["Total Time"]) ?? 0) / 1000
        let pos = num(info["Playback Position"]) ?? num(info["Player Position"])
        let trackID = info["Track ID"] as? String
        HWLog.write("müzik bildirimi: \(app) \(state) \(name) – \(artist)")
        apply(app: app, playing: state == "playing", name: name, artist: artist, album: album, duration: dur, position: pos, trackID: trackID)
    }

    private func apply(app: String, playing: Bool, name: String, artist: String, album: String, duration: Double, position: Double?, trackID: String?) {
        let key = "\(app)|\(name)|\(artist)"
        let changed = key != trackKey
        self.app = app; self.playing = playing
        self.title = name; self.artist = artist; self.album = album
        if duration > 0 { self.duration = duration }
        if let p = position { basePos = p } else if changed { basePos = 0 } else { basePos = self.position(at: Date()) }
        baseDate = Date()
        available = true
        if changed {
            trackKey = key
            artwork = nil
            loadArtwork(app: app, trackID: trackID, artist: artist, album: album, name: name, key: key)
        }
    }

    // MARK: Kapak resmi (izin gerektirmeyen genel servisler)

    private func loadArtwork(app: String, trackID: String?, artist: String, album: String, name: String, key: String) {
        Task {
            var data: Data?
            if app == "Spotify", let id = trackID, id.hasPrefix("spotify:track:"),
               let u = URL(string: "https://open.spotify.com/oembed?url=" + id),
               let (d, _) = try? await URLSession.shared.data(from: u),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let t = j["thumbnail_url"] as? String, let tu = URL(string: t) {
                data = try? await URLSession.shared.data(from: tu).0
            }
            if data == nil {
                var c = URLComponents(string: "https://itunes.apple.com/search")!
                c.queryItems = [.init(name: "term", value: "\(artist) \(album.isEmpty ? name : album)"), .init(name: "entity", value: "album"), .init(name: "limit", value: "1")]
                if let (d, _) = try? await URLSession.shared.data(from: c.url!),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let r = (j["results"] as? [[String: Any]])?.first, let a = r["artworkUrl100"] as? String,
                   let au = URL(string: a.replacingOccurrences(of: "100x100bb", with: "400x400bb")) {
                    data = try? await URLSession.shared.data(from: au).0
                }
            }
            guard let data, let img = NSImage(data: data), key == trackKey else { return }
            artwork = img
            tint = Self.averageColor(img)
        }
    }

    private static func averageColor(_ img: NSImage) -> Color {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let c = NSColor(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, max(0.35, sat * 1.25)), brightness: max(0.8, b))   // okunur, canlı ton
    }

    // MARK: AppleScript (yalnızca ilk durum sorgusu ve düğmeler)

    nonisolated private static func run(_ src: String) -> (String?, Int?) {
        var err: NSDictionary?
        guard let s = NSAppleScript(source: src) else { return (nil, nil) }
        let r = s.executeAndReturnError(&err)
        if let e = err { return (nil, e["NSAppleScriptErrorNumber"] as? Int) }
        return (r.stringValue, nil)
    }

    private func running(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Açılışta ya da kullanıcı yenileyince çalan parçayı sorgular (bildirimler yalnızca değişimde gelir)
    func refresh() {
        let sp = running("com.spotify.client"), mu = running("com.apple.Music")
        guard sp || mu else { clear(); return }
        queue.async {
            var results: [(String, String)] = []
            var denied = false
            if sp {
                let (r, e) = Self.run("""
                tell application "Spotify"
                  if player state is stopped then return ""
                  return (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track) & "||" & (duration of current track) & "||" & (player position as integer) & "||" & (id of current track)
                end tell
                """)
                if e == -1743 { denied = true } else if let r, !r.isEmpty { results.append(("Spotify", r)) }
            }
            if mu {
                let (r, e) = Self.run("""
                tell application "Music"
                  if player state is stopped then return ""
                  return (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track) & "||" & ((duration of current track) as integer) & "||" & (player position as integer) & "||"
                end tell
                """)
                if e == -1743 { denied = true } else if let r, !r.isEmpty { results.append(("Music", r)) }
            }
            DispatchQueue.main.async {
                Task { @MainActor in
                    self.note = denied ? "Parça bilgisi bildirimden gelir. İlerleme ve düğmeler için otomasyon izni gerekli." : nil
                    // Çalan varsa onu tercih et
                    let pick = results.first { $0.1.lowercased().hasPrefix("playing") } ?? results.first
                    guard let (app, raw) = pick else { return }
                    let p = raw.components(separatedBy: "||")
                    guard p.count >= 6 else { return }
                    HWLog.write("müzik sorgusu: \(app) \(p[0]) \(p[1])")
                    let dur = app == "Spotify" ? (Double(p[4]) ?? 0) / 1000 : (Double(p[4]) ?? 0)
                    self.apply(app: app, playing: p[0].lowercased() == "playing", name: p[1], artist: p[2], album: p[3],
                               duration: dur, position: Double(p[5]), trackID: p.count > 6 ? p[6] : nil)
                }
            }
        }
    }

    /// İzin penceresini bilinçli olarak tetikler (ayarlardaki düğme)
    func requestAutomationAccess() {
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func command(_ cmd: String) {
        guard !app.isEmpty else { return }
        let appName = app
        // Hemen tepki: oynat/duraklat anında görünsün
        if cmd == "playpause" { basePos = position(at: Date()); baseDate = Date(); playing.toggle() }
        queue.async {
            let (_, e) = Self.run("tell application \"\(appName)\" to \(cmd)")
            DispatchQueue.main.async {
                Task { @MainActor in
                    if e == -1743 {
                        self.note = "Düğmeler için izin gerekli: Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon → HavaliWidget."
                        if cmd == "playpause" { self.playing.toggle() }
                    }
                }
            }
        }
    }

    func seek(fraction: Double) {
        guard duration > 0, !app.isEmpty else { return }
        let sec = Int(max(0, min(1, fraction)) * duration)
        basePos = Double(sec); baseDate = Date()
        let appName = app
        queue.async { _ = Self.run("tell application \"\(appName)\" to set player position to \(sec)") }
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}

// MARK: - Döviz ve kripto (anahtarsız, ücretsiz servisler)

@MainActor
final class FinanceModel: ObservableObject {
    @Published var usd = 0.0
    @Published var eur = 0.0
    @Published var gbp = 0.0
    @Published var btc = 0.0
    @Published var btcChange = 0.0
    @Published var eth = 0.0
    @Published var ethChange = 0.0
    @Published var updated: Date?
    @Published var error: String?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func load() {
        Task {
            do {
                let (d, _) = try await URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!)
                if let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let r = j["rates"] as? [String: Double], let tl = r["TRY"] {
                    usd = tl
                    eur = tl / (r["EUR"] ?? 1)
                    gbp = tl / (r["GBP"] ?? 1)
                }
                let (c, _) = try await URLSession.shared.data(from: URL(string:
                    "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true")!)
                if let j = try JSONSerialization.jsonObject(with: c) as? [String: Any] {
                    if let b = j["bitcoin"] as? [String: Double] { btc = b["usd"] ?? 0; btcChange = b["usd_24h_change"] ?? 0 }
                    if let e = j["ethereum"] as? [String: Double] { eth = e["usd"] ?? 0; ethChange = e["usd_24h_change"] ?? 0 }
                }
                updated = Date(); error = nil
            } catch { self.error = "Bağlantı yok" }
        }
    }
}

// MARK: - Disk ve ağ

@MainActor
final class NetDiskModel: ObservableObject {
    @Published var diskUsed = 0.0
    @Published var diskFreeText = ""
    @Published var down = 0.0      // bayt/sn
    @Published var up = 0.0
    private var timer: Timer?
    private var last: (rx: UInt64, tx: UInt64, t: Date)?

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; last = nil }

    private func counters() -> (UInt64, UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en"), let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
            }
            p = ifa.pointee.ifa_next
        }
        return (rx, tx)
    }

    private func tick() {
        let now = Date()
        let c = counters()
        if let l = last {
            let dt = now.timeIntervalSince(l.t)
            if dt > 0 {
                down = Double(c.0 &- l.rx) / dt
                up = Double(c.1 &- l.tx) / dt
            }
        }
        last = (c.0, c.1, now)
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        if let total = v?.volumeTotalCapacity, let free = v?.volumeAvailableCapacityForImportantUsage, total > 0 {
            diskUsed = 1 - Double(free) / Double(total)
            diskFreeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " boş"
        }
    }

    static func speed(_ b: Double) -> String {
        if b > 1_000_000 { return String(format: "%.1f MB/s", b / 1_000_000) }
        return String(format: "%.0f KB/s", b / 1000)
    }
}

// MARK: - Takvim etkinlikleri (EventKit)

struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let location: String?
    let calendarID: String
}

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    let color: Color
}

enum CalendarAccess { case unknown, notDetermined, granted, denied }

@MainActor
final class AgendaModel: ObservableObject {
    @Published var access: CalendarAccess = .unknown
    @Published var events: [AgendaEvent] = []
    @Published var calendars: [CalendarInfo] = []
    @Published var updated: Date?

    private let ek = EKEventStore()
    private var timer: Timer?
    private var token: NSObjectProtocol?

    private func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied          // denied, restricted, writeOnly
        }
    }

    func start() {
        guard timer == nil else { return }
        access = currentAccess()
        HWLog.write("takvim durumu: \(access)")
        if access == .notDetermined { requestAccess() } else if access == .granted { refresh() }
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let t = token { NotificationCenter.default.removeObserver(t); token = nil }
    }

    /// İzin penceresini gösterir (uygulama arka plan türünde olduğu için önce öne getirilir)
    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            let ok = (try? await ek.requestFullAccessToEvents()) ?? false
            access = ok ? .granted : currentAccess()
            HWLog.write("takvim izni sonucu: \(access)")
            if ok { refresh() }
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    func refresh() {
        access = currentAccess()
        guard access == .granted else { return }
        let store = Store.shared
        let cals = ek.calendars(for: .event)
        calendars = cals.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color ?? .systemBlue)) }
            .sorted { $0.title < $1.title }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: max(1, store.s.agendaDays), to: Calendar.current.startOfDay(for: now))!
        let visible = cals.filter { !store.s.hiddenCalendars.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { events = []; return }
        let pred = ek.predicateForEvents(withStart: Calendar.current.startOfDay(for: now), end: end, calendars: visible)
        events = ek.events(matching: pred)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .sorted { $0.startDate < $1.startDate }
            .map { AgendaEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                               title: ($0.title ?? "").isEmpty ? "Etkinlik" : $0.title,
                               start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                               color: Color(nsColor: $0.calendar.color ?? .systemBlue),
                               location: ($0.location ?? "").isEmpty ? nil : $0.location,
                               calendarID: $0.calendar.calendarIdentifier) }
        updated = now
        HWLog.write("takvim: \(events.count) etkinlik, \(calendars.count) takvim")
    }
}

// MARK: - Pomodoro

@MainActor
final class PomodoroModel: ObservableObject {
    @Published var remaining = 25 * 60
    @Published var running = false
    @Published var focusMode = true
    @Published var completed = 0
    private var timer: Timer?

    func configure(focus: Int, rest: Int) {
        if !running { remaining = (focusMode ? focus : rest) * 60 }
    }

    func toggle(focus: Int, rest: Int) {
        running.toggle()
        timer?.invalidate()
        if running {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick(focus: focus, rest: rest) }
            }
        }
    }

    func reset(focus: Int, rest: Int) {
        running = false; timer?.invalidate()
        remaining = (focusMode ? focus : rest) * 60
    }

    func switchMode(focus: Int, rest: Int) {
        running = false; timer?.invalidate()
        focusMode.toggle()
        remaining = (focusMode ? focus : rest) * 60
    }

    private func tick(focus: Int, rest: Int) {
        guard running else { return }
        remaining -= 1
        if remaining <= 0 {
            NSSound.beep()
            if focusMode { completed += 1 }
            focusMode.toggle()
            remaining = (focusMode ? focus : rest) * 60
        }
    }
}

// MARK: - Ay evresi (yerel hesap)

struct MoonInfo {
    let name: String
    let symbol: String
    let illumination: Double
    let ageDays: Double

    static func at(_ date: Date) -> MoonInfo {
        let synodic = 29.530588853
        let ref = Date(timeIntervalSince1970: 947182440)    // 6 Ocak 2000 18:14 UTC (yeni ay)
        var age = date.timeIntervalSince(ref) / 86400
        age = age.truncatingRemainder(dividingBy: synodic)
        if age < 0 { age += synodic }
        let frac = age / synodic
        let illum = (1 - cos(2 * Double.pi * frac)) / 2
        let (name, sym): (String, String)
        switch frac {
        case ..<0.03, 0.97...: (name, sym) = ("Yeni Ay", "🌑")
        case ..<0.22: (name, sym) = ("Hilal (büyüyen)", "🌒")
        case ..<0.28: (name, sym) = ("İlk Dördün", "🌓")
        case ..<0.47: (name, sym) = ("Şişkin Ay (büyüyen)", "🌔")
        case ..<0.53: (name, sym) = ("Dolunay", "🌕")
        case ..<0.72: (name, sym) = ("Şişkin Ay (küçülen)", "🌖")
        case ..<0.78: (name, sym) = ("Son Dördün", "🌗")
        default: (name, sym) = ("Hilal (küçülen)", "🌘")
        }
        return MoonInfo(name: name, symbol: sym, illumination: illum, ageDays: age)
    }
}

// MARK: - Fotoğraf çerçevesi

enum PhotoFrame {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HavaliWidget/photos")
    }

    static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @MainActor static func pick() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        var picked: [URL] = []
        for u in p.urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                let kids = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
                picked += kids.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains($0.pathExtension.lowercased()) }
            } else { picked.append(u) }
        }
        guard !picked.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        var copied = 0
        for (i, f) in picked.prefix(60).enumerated() {
            if (try? FileManager.default.copyItem(at: f, to: dir.appendingPathComponent(String(format: "p%d_%03d.", stamp, i) + f.pathExtension))) != nil { copied += 1 }
        }
        guard copied > 0 else { return }
        for old in files where !old.lastPathComponent.hasPrefix("p\(stamp)_") { try? FileManager.default.removeItem(at: old) }
        PhotoCache.shared.reset()
    }
}

final class PhotoCache {
    static let shared = PhotoCache()
    private var store: [URL: CGImage] = [:]
    private let lock = NSLock()

    func image(_ u: URL) -> CGImage? {
        lock.lock(); if let c = store[u] { lock.unlock(); return c }; lock.unlock()
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 900]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        lock.lock(); if store.count > 3 { store.removeAll() }; store[u] = img; lock.unlock()
        return img
    }

    func reset() { lock.lock(); store.removeAll(); lock.unlock() }
}
