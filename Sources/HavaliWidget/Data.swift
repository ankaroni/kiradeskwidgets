import Foundation
import IOKit.ps
import Darwin

// MARK: - Sistem durumu

final class SystemStats: ObservableObject {
    @Published var cpu = 0.0
    @Published var ram = 0.0
    @Published var ramText = ""
    @Published var battery = -1.0      // -1: pil yok
    @Published var charging = false

    private var prev: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        cpu = readCPU()
        readRAM()
        readBattery()
    }

    private func readCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return cpu }
        let cur = (user: info.cpu_ticks.0, sys: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { prev = cur }
        guard let p = prev else { return 0 }
        let du = Double(cur.user &- p.user), ds = Double(cur.sys &- p.sys)
        let di = Double(cur.idle &- p.idle), dn = Double(cur.nice &- p.nice)
        let total = du + ds + di + dn
        return total > 0 ? (du + ds + dn) / total : 0
    }

    private func readRAM() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var st = vm_statistics64()
        let r = withUnsafeMutablePointer(to: &st) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = (Double(st.active_count) + Double(st.wire_count) + Double(st.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        ram = min(1, used / total)
        ramText = String(format: "%.1f / %.0f GB", used / 1_073_741_824, total / 1_073_741_824)
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            battery = Double(cap) / 100
            charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            return
        }
    }
}

// MARK: - Hava durumu (Open-Meteo: anahtarsız, ücretsiz)

struct DayForecast: Identifiable {
    let id = UUID()
    let label: String
    let code: Int
    let max: Double
    let min: Double
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published var city = ""
    @Published var temp = 0.0
    @Published var feels = 0.0
    @Published var code = 0
    @Published var wind = 0.0
    @Published var hourly: [Double] = []
    @Published var sunrise = ""
    @Published var sunset = ""
    @Published var dayLength: String?
    @Published var days: [DayForecast] = []
    @Published var error: String?
    @Published var loaded = false

    private var timer: Timer?
    private var lastCity = ""

    func start(city: String) {
        load(city: city)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load(city: self?.lastCity ?? city) }
        }
    }

    func load(city: String) {
        lastCity = city
        let name = city.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Şehir girin"; return }
        Task {
            do {
                var gc = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                gc.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1"), .init(name: "language", value: "tr")]
                let (gd, _) = try await URLSession.shared.data(from: gc.url!)
                guard let g = try JSONSerialization.jsonObject(with: gd) as? [String: Any],
                      let res = (g["results"] as? [[String: Any]])?.first,
                      let lat = res["latitude"] as? Double, let lon = res["longitude"] as? Double else {
                    self.error = "Şehir bulunamadı"; return
                }
                var fc = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                fc.queryItems = [
                    .init(name: "latitude", value: "\(lat)"), .init(name: "longitude", value: "\(lon)"),
                    .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
                    .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
                    .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "4"),
                    .init(name: "hourly", value: "temperature_2m"), .init(name: "forecast_hours", value: "13"),
                ]
                let (fd, _) = try await URLSession.shared.data(from: fc.url!)
                guard let f = try JSONSerialization.jsonObject(with: fd) as? [String: Any],
                      let cur = f["current"] as? [String: Any], let daily = f["daily"] as? [String: Any],
                      let times = daily["time"] as? [String], let codes = daily["weather_code"] as? [Int],
                      let mx = daily["temperature_2m_max"] as? [Double], let mn = daily["temperature_2m_min"] as? [Double] else {
                    self.error = "Veri okunamadı"; return
                }
                self.city = (res["name"] as? String) ?? name
                self.temp = cur["temperature_2m"] as? Double ?? 0
                self.feels = cur["apparent_temperature"] as? Double ?? 0
                self.code = cur["weather_code"] as? Int ?? 0
                self.wind = cur["wind_speed_10m"] as? Double ?? 0
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                let out = DateFormatter(); out.locale = Locale(identifier: "tr_TR"); out.dateFormat = "EEE"
                self.days = (1..<min(4, times.count)).compactMap { i in
                    guard let d = df.date(from: times[i]) else { return nil }
                    return DayForecast(label: out.string(from: d), code: codes[i], max: mx[i], min: mn[i])
                }
                if let sr = (daily["sunrise"] as? [String])?.first, let ss = (daily["sunset"] as? [String])?.first {
                    self.sunrise = String(sr.suffix(5)); self.sunset = String(ss.suffix(5))
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
                    if let a = f.date(from: sr), let b = f.date(from: ss) {
                        let m = Int(b.timeIntervalSince(a) / 60)
                        self.dayLength = "\(m / 60) sa \(m % 60) dk"
                    }
                }
                self.hourly = ((f["hourly"] as? [String: Any])?["temperature_2m"] as? [Double]) ?? []
                self.error = nil
                self.loaded = true
            } catch {
                self.error = "Bağlantı yok"
            }
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Açık"
        case 1: return "Çoğunlukla açık"
        case 2: return "Parçalı bulutlu"
        case 3: return "Kapalı"
        case 45, 48: return "Sisli"
        case 51...57: return "Çiseleme"
        case 61...67: return "Yağmurlu"
        case 80...82: return "Sağanak"
        case 71...77, 85, 86: return "Karlı"
        case 95...99: return "Gök gürültülü"
        default: return "Bulutlu"
        }
    }
}
