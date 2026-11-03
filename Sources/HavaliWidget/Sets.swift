import SwiftUI
import AppKit

struct SetItem {
    let kind: WidgetKind
    var style: CardStyle
    var scale = 1.0
}

enum ColAlign { case top, center, bottom }

/// Düzenin bir sütunu: ekranda yatayda `x` oranına (0 = sol, 1 = sağ) yerleşir, dikeyde hizalanır
struct SetColumn {
    var x: Double = 0
    var align: ColAlign = .top
    var items: [SetItem]
}

struct LayoutSet: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let hue: Double
    let columns: [SetColumn]
    var items: [SetItem] { columns.flatMap(\.items) }
}

let layoutSets: [LayoutSet] = [
    LayoutSet(id: "minimal", name: "Minimal Sabah", subtitle: "Dev dikey saat, hava ve söz. Kutu yok, sadece tipografi.",
              icon: "sun.horizon", hue: 0.07, columns: [
        SetColumn(x: 0.0, align: .center, items: [SetItem(kind: .bigClock, style: .clear)]),
        SetColumn(x: 0.52, align: .bottom, items: [SetItem(kind: .weather, style: .clear)]),
        SetColumn(x: 1.0, align: .top, items: [SetItem(kind: .quote, style: .clear)]),
    ]),
    LayoutSet(id: "aurora", name: "Aurora", subtitle: "Renk geçişli, buzlu cam kartlar.",
              icon: "sparkles", hue: 0.52, columns: [
        SetColumn(x: 0.0, align: .top, items: [SetItem(kind: .clock, style: .aurora), SetItem(kind: .weather, style: .aurora)]),
        SetColumn(x: 0.5, align: .bottom, items: [SetItem(kind: .calendar, style: .aurora), SetItem(kind: .sunmoon, style: .aurora)]),
        SetColumn(x: 1.0, align: .top, items: [SetItem(kind: .rings, style: .aurora)]),
    ]),
    LayoutSet(id: "neon", name: "Siber Neon", subtitle: "Karanlık zemin, parlayan neon kenarlar.",
              icon: "bolt.fill", hue: 0.88, columns: [
        SetColumn(x: 0.0, align: .top, items: [SetItem(kind: .clock, style: .neon), SetItem(kind: .system, style: .neon), SetItem(kind: .diskNet, style: .neon)]),
        SetColumn(x: 0.55, align: .center, items: [SetItem(kind: .weather, style: .neon), SetItem(kind: .finance, style: .neon)]),
    ]),
    LayoutSet(id: "pastel", name: "Pastel Gün", subtitle: "Açık, yumuşak renkli kartlar, koyu yazı.",
              icon: "heart.fill", hue: 0.93, columns: [
        SetColumn(x: 0.0, align: .top, items: [SetItem(kind: .clock, style: .matte), SetItem(kind: .weather, style: .matte)]),
        SetColumn(x: 0.5, align: .bottom, items: [SetItem(kind: .calendar, style: .matte)]),
        SetColumn(x: 1.0, align: .top, items: [SetItem(kind: .todo, style: .frost), SetItem(kind: .quote, style: .matte)]),
    ]),
    LayoutSet(id: "focus", name: "Odak Modu", subtitle: "Pomodoro, yapılacaklar, geri sayım.",
              icon: "scope", hue: 0.36, columns: [
        SetColumn(x: 0.0, align: .center, items: [SetItem(kind: .pomodoro, style: .gradient), SetItem(kind: .todo, style: .dark)]),
        SetColumn(x: 0.5, align: .top, items: [SetItem(kind: .clock, style: .clear)]),
        SetColumn(x: 1.0, align: .bottom, items: [SetItem(kind: .countdown, style: .gradient), SetItem(kind: .quote, style: .dark)]),
    ]),
    LayoutSet(id: "night", name: "Gece Salonu", subtitle: "Analog saat, müzik, ay ve dünya saatleri.",
              icon: "moon.stars.fill", hue: 0.64, columns: [
        SetColumn(x: 0.0, align: .top, items: [SetItem(kind: .analog, style: .glass), SetItem(kind: .world, style: .glass)]),
        SetColumn(x: 0.7, align: .bottom, items: [SetItem(kind: .nowPlaying, style: .glass), SetItem(kind: .sunmoon, style: .glass)]),
    ]),
    LayoutSet(id: "dashboard", name: "Dashboard", subtitle: "Sistem, ağ, piyasa, hava. Her şey tek bakışta.",
              icon: "square.grid.2x2.fill", hue: 0.56, columns: [
        SetColumn(x: 0.0, align: .top, items: [SetItem(kind: .weather, style: .dark), SetItem(kind: .agenda, style: .dark)]),
        SetColumn(x: 0.5, align: .top, items: [SetItem(kind: .rings, style: .dark), SetItem(kind: .diskNet, style: .dark)]),
        SetColumn(x: 1.0, align: .top, items: [SetItem(kind: .finance, style: .dark), SetItem(kind: .system, style: .dark)]),
    ]),
]

/// Sütun tabanlı bento dizilim: sütunlar ekrana yayılır, dikeyde farklı hizalanır, sığmazsa hepsi küçülür
enum AutoLayout {
    struct Plan {
        var frames: [WidgetKind: CGRect]   // ekran koordinatı (sol-alt köşe)
        var fit: Double                    // uygulanan küçültme çarpanı (1 = hiç küçülmedi)
    }

    static func plan(_ columns: [SetColumn], in vf: CGRect, boost: Bool = true) -> Plan {
        let margin = max(36.0, vf.width * 0.022)
        let reserve = vf.width * 0.08          // sağ kenardaki masaüstü simgeleri için boş şerit
        let gap = 22.0
        let availH = vf.height - 2 * margin
        let usableX = vf.minX + margin
        let usableW = vf.width - 2 * margin - reserve

        func sizes(_ c: SetColumn, _ fit: Double) -> [CGSize] {
            c.items.map { CGSize(width: $0.kind.baseSize.width * $0.scale * fit, height: $0.kind.baseSize.height * $0.scale * fit) }
        }
        func colHeight(_ c: SetColumn, _ fit: Double) -> Double {
            let hs = sizes(c, fit).map(\.height)
            return hs.reduce(0, +) + gap * Double(max(0, hs.count - 1))
        }
        func colWidth(_ c: SetColumn, _ fit: Double) -> Double { Double(sizes(c, fit).map(\.width).max() ?? 0) }
        func xOf(_ c: SetColumn, _ fit: Double) -> Double { usableX + c.x * max(0, usableW - colWidth(c, fit)) }

        // Sığana kadar küçült: yükseklik ve sütunların yatay çakışması
        // Büyük ekranlarda widget'lar küçük kalmasın: ekran boyutuna göre 1.5×'e kadar büyüt
        var fit = boost ? min(1.5, max(1.0, min(vf.width / 1800, vf.height / 1100))) : 1.0
        for c in columns { let h = colHeight(c, fit); if h > availH { fit = min(fit, fit * availH / h) } }
        func overlaps(_ f: Double) -> Bool {
            let sorted = columns.sorted { $0.x < $1.x }
            for i in 1..<max(1, sorted.count) {
                let prevRight = xOf(sorted[i - 1], f) + colWidth(sorted[i - 1], f)
                if xOf(sorted[i], f) < prevRight + 18 { return true }
            }
            return false
        }
        while overlaps(fit) && fit > 0.45 { fit -= 0.04 }
        fit = max(fit, 0.45)

        var frames: [WidgetKind: CGRect] = [:]
        for c in columns {
            let sz = sizes(c, fit)
            let colW = colWidth(c, fit)
            let x0 = xOf(c, fit)
            let total = colHeight(c, fit)
            var y: Double
            switch c.align {
            case .top: y = vf.maxY - margin
            case .bottom: y = vf.minY + margin + total
            case .center: y = vf.midY + total / 2
            }
            for (i, it) in c.items.enumerated() {
                let s = sz[i]
                frames[it.kind] = CGRect(x: x0 + (colW - s.width) / 2, y: y - s.height, width: s.width, height: s.height)
                y -= s.height + gap
            }
        }
        return Plan(frames: frames, fit: fit)
    }

    /// Açık widget'ları sırayla sütunlara doldurur, sütunları ekrana eşit yayar
    static func autoColumns(_ kinds: [(WidgetKind, Double)], in vf: CGRect) -> [SetColumn] {
        let margin = max(36.0, vf.width * 0.022), gap = 22.0
        let availH = vf.height - 2 * margin
        var groups: [[SetItem]] = []
        var cur: [SetItem] = []
        var h = 0.0
        for (k, sc) in kinds {
            let it = SetItem(kind: k, style: .glass, scale: sc)
            let ih = k.baseSize.height * sc
            if !cur.isEmpty && h + gap + ih > availH { groups.append(cur); cur = []; h = 0 }
            h += (cur.isEmpty ? 0 : gap) + ih
            cur.append(it)
        }
        if !cur.isEmpty { groups.append(cur) }
        let n = groups.count
        return groups.enumerated().map { i, g in
            SetColumn(x: n > 1 ? Double(i) / Double(n - 1) : 0, align: .top, items: g)
        }
    }
}
