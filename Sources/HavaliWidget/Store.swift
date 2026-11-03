import SwiftUI
import ServiceManagement

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case clock, bigClock, analog, world, calendar, agenda, weather, sunmoon, system, rings, diskNet
    case nowPlaying, todo, countdown, finance, pomodoro, photo, quote, note
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Saat"
        case .bigClock: "Dev Saat (dikey)"
        case .analog: "Analog Saat"
        case .world: "Dünya Saati"
        case .calendar: "Takvim"
        case .agenda: "Ajanda (Takvim etkinlikleri)"
        case .weather: "Hava Durumu"
        case .sunmoon: "Güneş ve Ay"
        case .system: "Sistem (CPU/RAM/Pil)"
        case .rings: "Halkalar (iç içe)"
        case .diskNet: "Disk ve Ağ"
        case .nowPlaying: "Müzik Çalar"
        case .todo: "Yapılacaklar"
        case .countdown: "Geri Sayım"
        case .finance: "Döviz ve Kripto"
        case .pomodoro: "Pomodoro"
        case .photo: "Fotoğraf Çerçevesi"
        case .quote: "Günün Sözü"
        case .note: "Not"
        }
    }

    var icon: String {
        switch self {
        case .clock: "clock"
        case .bigClock: "textformat.size"
        case .analog: "clock.circle"
        case .world: "globe"
        case .calendar: "calendar"
        case .agenda: "list.bullet.rectangle"
        case .weather: "cloud.sun"
        case .sunmoon: "moon.stars"
        case .system: "cpu"
        case .rings: "circle.circle"
        case .diskNet: "internaldrive"
        case .nowPlaying: "music.note"
        case .todo: "checklist"
        case .countdown: "hourglass"
        case .finance: "turkishlirasign.circle"
        case .pomodoro: "timer"
        case .photo: "photo"
        case .quote: "quote.opening"
        case .note: "note.text"
        }
    }

    /// Ölçek 1.0 iken pencere boyutu
    var baseSize: CGSize {
        switch self {
        case .clock: CGSize(width: 340, height: 150)
        case .bigClock: CGSize(width: 250, height: 330)
        case .analog: CGSize(width: 240, height: 240)
        case .world: CGSize(width: 320, height: 200)
        case .calendar: CGSize(width: 290, height: 310)
        case .agenda: CGSize(width: 340, height: 270)
        case .weather: CGSize(width: 330, height: 280)
        case .sunmoon: CGSize(width: 320, height: 150)
        case .system: CGSize(width: 320, height: 130)
        case .rings: CGSize(width: 250, height: 280)
        case .diskNet: CGSize(width: 320, height: 130)
        case .nowPlaying: CGSize(width: 370, height: 170)
        case .todo: CGSize(width: 300, height: 250)
        case .countdown: CGSize(width: 280, height: 150)
        case .finance: CGSize(width: 320, height: 210)
        case .pomodoro: CGSize(width: 260, height: 220)
        case .photo: CGSize(width: 300, height: 240)
        case .quote: CGSize(width: 340, height: 160)
        case .note: CGSize(width: 280, height: 170)
        }
    }
}

enum CardStyle: String, CaseIterable, Identifiable, Codable {
    case glass, dark, aurora, neon, matte, frost, gradient, clear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: "Cam"
        case .dark: "Koyu"
        case .aurora: "Aurora"
        case .neon: "Neon"
        case .matte: "Pastel"
        case .frost: "Buzul"
        case .gradient: "Gradyan"
        case .clear: "Şeffaf"
        }
    }
}

/// Stile göre yazı rengi (açık yüzeylerde koyu, diğerlerinde beyaz)
func inkColor(_ style: CardStyle) -> Color {
    switch style {
    case .matte, .frost: return Color(white: 0.11)
    default: return .white
    }
}

/// Widget'ların masaüstü simgelerine göre konumu
enum Placement: String, CaseIterable, Identifiable, Codable {
    case behind, front
    var id: String { rawValue }
    var title: String {
        switch self {
        case .behind: "Simgelerin arkasında (önerilen)"
        case .front: "Simgelerin üstünde (tıklanabilir)"
        }
    }
}

struct WidgetConfig: Codable, Equatable {
    var enabled = false
    var scale = 1.0
    var style = CardStyle.glass
    var opacity = 1.0
    /// Simgelerin üstüne çıkar ve tıklanabilir olur (müzik düğmeleri, görevler, pomodoro...)
    var clickable = false
}

/// Tıklanması anlamlı olan widget'lar
let interactiveKinds: [WidgetKind] = [.nowPlaying, .todo, .pomodoro, .agenda, .quote]

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

struct Settings: Codable, Equatable {
    var configs: [String: WidgetConfig] = {
        var d: [String: WidgetConfig] = [:]
        for k in WidgetKind.allCases { d[k.rawValue] = WidgetConfig(enabled: k == .clock || k == .weather, clickable: interactiveKinds.contains(k)) }
        return d
    }()
    var city = "Istanbul"
    var accentHue = 0.52
    var locked = false
    var placement = Placement.behind
    var screenIndex = 0
    var clock24h = true
    var showSeconds = false
    var analogSeconds = true
    var noteText = "Bugün için bir not yaz ✍️"
    var worldZones = ["Europe/Istanbul", "Europe/London", "America/New_York", "Asia/Tokyo"]
    var todos = [Todo(text: "Su iç 💧"), Todo(text: "Yürüyüşe çık"), Todo(text: "Mail'lere bak")]
    var countdownTitle = "Yılbaşı"
    var countdownDate = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1)) ?? Date()
    var showCrypto = true
    var pomodoroFocus = 25
    var pomodoroBreak = 5
    var photoInterval = 12.0
    var agendaDays = 7
    var hiddenCalendars: [String] = []
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var s: Settings {
        didSet {
            if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "settings2") }
        }
    }
    @Published var allHidden = false
    /// Konumları düzenleme modu: widget'lar geçici olarak simgelerin üstüne çıkar ve sürüklenebilir
    @Published var editing = false
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { /* imzasız uygulamada başarısız olabilir */ }
        }
    }

    private init() {
        s = Store.loadSettings()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Kayıtlı ayarları varsayılanlarla birleştirerek yükler: sonradan eklenen alanlar eski ayarları bozmaz
    private static func loadSettings() -> Settings {
        guard let saved = UserDefaults.standard.data(forKey: "settings2"),
              let savedObj = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defData = try? JSONEncoder().encode(Settings()),
              var merged = try? JSONSerialization.jsonObject(with: defData) as? [String: Any] else { return Settings() }
        for (k, v) in savedObj {
            if k == "configs", let sc = v as? [String: Any], var mc = merged["configs"] as? [String: Any] {
                for (kind, cfg) in sc {
                    if let c = cfg as? [String: Any], var base = mc[kind] as? [String: Any] {
                        for (ck, cv) in c { base[ck] = cv }
                        mc[kind] = base
                    } else { mc[kind] = cfg }
                }
                merged["configs"] = mc
            } else { merged[k] = v }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let v = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return v
    }

    func config(_ k: WidgetKind) -> WidgetConfig { s.configs[k.rawValue] ?? WidgetConfig() }

    func binding(_ k: WidgetKind) -> Binding<WidgetConfig> {
        Binding(get: { self.config(k) }, set: { self.s.configs[k.rawValue] = $0 })
    }

    var accent: Color { Color(hue: s.accentHue, saturation: 0.55, brightness: 1) }

    /// Kartın zeminine göre okunur vurgu rengi (gradyanda beyaz, açık kartlarda koyu ton)
    func accent(on style: CardStyle) -> Color {
        switch style {
        case .gradient: return .white
        case .matte, .frost: return Color(hue: s.accentHue, saturation: 0.75, brightness: 0.70)
        default: return accent
        }
    }

    /// Tüm widget'lara aynı görünümü uygula
    func applyStyleToAll(_ st: CardStyle) {
        for k in WidgetKind.allCases { var c = config(k); c.style = st; s.configs[k.rawValue] = c }
    }
}

/// Dünya saati için şehir listesi
let worldCities: [(name: String, tz: String)] = [
    ("İstanbul", "Europe/Istanbul"), ("Sofya", "Europe/Sofia"), ("Londra", "Europe/London"),
    ("Paris", "Europe/Paris"), ("Berlin", "Europe/Berlin"), ("Moskova", "Europe/Moscow"),
    ("Kahire", "Africa/Cairo"), ("Dubai", "Asia/Dubai"), ("Mumbai", "Asia/Kolkata"),
    ("Pekin", "Asia/Shanghai"), ("Tokyo", "Asia/Tokyo"), ("Seul", "Asia/Seoul"),
    ("Sidney", "Australia/Sydney"), ("New York", "America/New_York"), ("Chicago", "America/Chicago"),
    ("Los Angeles", "America/Los_Angeles"), ("São Paulo", "America/Sao_Paulo"), ("Toronto", "America/Toronto"),
]

let dailyQuotes: [(String, String)] = [
    ("Yolculuk, varışın kendisinden daha önemlidir.", "Atasözü"),
    ("Hayat, sen plan yaparken başına gelenlerdir.", "John Lennon"),
    ("Başlamak için mükemmel olmak zorunda değilsin, ama mükemmel olmak için başlamak zorundasın.", "Zig Ziglar"),
    ("Yarın, bugünden kalan işlerin adıdır.", "Atasözü"),
    ("Düşün, ama dünyayı değiştirmeyi unutma.", "Mustafa Kemal Atatürk"),
    ("Hayal gücü bilgiden daha önemlidir.", "Albert Einstein"),
    ("Küçük adımlar bile seni hedefe yaklaştırır.", "Lao Tzu"),
    ("Başarı, her gün tekrarlanan küçük çabaların toplamıdır.", "Robert Collier"),
    ("Cesaret, korkunun yokluğu değil, ona rağmen yürümektir.", "Nelson Mandela"),
    ("Kendin ol; diğerleri zaten alınmış.", "Oscar Wilde"),
    ("Bugünün işini yarına bırakma.", "Atasözü"),
    ("Yapabileceğine inan, yolun yarısını geçtin demektir.", "Theodore Roosevelt"),
    ("Sakin deniz usta denizci yetiştirmez.", "Atasözü"),
    ("Önce kendini dinle, sonra dünyayı.", "Anonim"),
    ("Her gün biraz daha iyi.", "Anonim"),
    ("Zaman, en değerli harcamadır.", "Theophrastus"),
    ("Yavaş git ama asla durma.", "Konfüçyüs"),
    ("Merak, bilginin anasıdır.", "Anonim"),
    ("Düşmek değil, kalkmamak yenilgidir.", "Konfüçyüs"),
    ("İyi işler sessizce büyür.", "Anonim"),
]
