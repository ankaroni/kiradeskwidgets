import SwiftUI

// MARK: - Ortak parçalar

struct Panel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let s = subtitle { Text(s).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// Stil seçici: her stilin küçük bir görsel örneğiyle
struct StyleChips: View {
    @Binding var selection: CardStyle
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
            ForEach(CardStyle.allCases) { st in
                Button { selection = st } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            LinearGradient(colors: [Color(hue: 0.60, saturation: 0.6, brightness: 0.5), Color(hue: 0.85, saturation: 0.55, brightness: 0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            CardBackground(style: st, radius: 12, grain: false).padding(7)
                            Text("Aa").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(inkColor(st))
                        }
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selection == st ? Color.accentColor : .clear, lineWidth: 2.5))
                        Text(st.title).font(.system(size: 11, weight: selection == st ? .semibold : .regular))
                            .foregroundStyle(selection == st ? Color.primary : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { "\(Int($0 * 100))%" }
    var body: some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value)).font(.system(size: 12)).monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Ana pencere

enum SettingsPage: String, CaseIterable, Identifiable {
    case sets, widgets, look, desktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sets: "Hazır Setler"
        case .widgets: "Widget'lar"
        case .look: "Görünüm"
        case .desktop: "Masaüstü"
        }
    }
    var icon: String {
        switch self {
        case .sets: "wand.and.stars"
        case .widgets: "square.grid.2x2"
        case .look: "paintpalette"
        case .desktop: "display"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @State private var page: SettingsPage?
    @State private var selectedKind: WidgetKind = .clock

    init() {
        // Test/kısayol: --page sets|widgets|look|desktop ve --kind <widget>
        let a = CommandLine.arguments
        var pg: SettingsPage = .sets
        if let i = a.firstIndex(of: "--page"), i + 1 < a.count, let p = SettingsPage(rawValue: a[i + 1]) { pg = p }
        var k: WidgetKind = .clock
        if let i = a.firstIndex(of: "--kind"), i + 1 < a.count, let kk = WidgetKind(rawValue: a[i + 1]) { k = kk }
        _page = State(initialValue: pg)
        _selectedKind = State(initialValue: k)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { p in
                Label(p.title, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page ?? .sets {
                    case .sets: SetsPage()
                    case .widgets: WidgetsPage(selected: $selectedKind)
                    case .look: LookPage()
                    case .desktop: DesktopPage()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background)
        }
        .frame(minWidth: 880, minHeight: 600)
    }
}

// MARK: - Sayfa: Hazır setler

struct SetCard: View {
    let set: LayoutSet
    var body: some View {
        let vf = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let plan = AutoLayout.plan(set.columns, in: vf)
        let styles = Dictionary(uniqueKeysWithValues: set.items.map { ($0.kind, $0.style) })
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let k = geo.size.width / vf.width
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hue: set.hue, saturation: 0.55, brightness: 0.35),
                                            Color(hue: set.hue + 0.18, saturation: 0.6, brightness: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    ForEach(Array(plan.frames.keys), id: \.self) { kind in
                        if let r = plan.frames[kind] {
                            ZStack {
                                CardBackground(style: styles[kind] ?? .glass, radius: 8, grain: false, hueOverride: set.hue)
                                Image(systemName: kind.icon).font(.system(size: max(8, r.height * k * 0.28)))
                                    .foregroundStyle(inkColor(styles[kind] ?? .glass).opacity(0.85))
                            }
                            .frame(width: r.width * k, height: r.height * k)
                            .offset(x: r.minX * k, y: (vf.height - r.maxY) * k)
                        }
                    }
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Image(systemName: set.icon).foregroundStyle(Color(hue: set.hue, saturation: 0.6, brightness: 1))
                Text(set.name).font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(set.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 30, alignment: .topLeading)
            Button { WidgetManager.shared.apply(set: set) } label: {
                Text("Uygula").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Color(hue: set.hue, saturation: 0.65, brightness: 0.85))
            .controlSize(.regular)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct SetsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hazır Setler").font(.system(size: 26, weight: .bold))
            Text("Bir set seçin: widget'lar, renkler ve stiller otomatik ayarlanır, masaüstüne düzenli dizilir. Ekrana sığmazsa küçültülür.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
            ForEach(layoutSets) { SetCard(set: $0) }
        }
        Panel(title: "Kendi düzeniniz", subtitle: "Zaten açık olan widget'ları bozmadan düzenli sütunlara dizer.") {
            Button { WidgetManager.shared.autoArrangeCurrent() } label: { Label("Açık widget'ları düzenli diz", systemImage: "rectangle.grid.2x2") }
        }
    }
}

// MARK: - Sayfa: Widget'lar

struct WidgetsPage: View {
    @ObservedObject private var store = Store.shared
    @Binding var selected: WidgetKind

    var body: some View {
        Text("Widget'lar").font(.system(size: 26, weight: .bold))
        HStack(alignment: .top, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                ForEach(WidgetKind.allCases) { k in
                    let on = store.config(k).enabled
                    Button { selected = k } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: k.icon).font(.system(size: 18)).foregroundStyle(on ? Color.accentColor : .secondary)
                                Spacer()
                                Toggle("", isOn: store.binding(k).enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            }
                            Text(k.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                        }
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.secondary))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected == k ? Color.accentColor : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 300)

            WidgetDetail(kind: selected).frame(width: 330)
        }
    }
}

struct WidgetDetail: View {
    @ObservedObject private var store = Store.shared
    let kind: WidgetKind
    @State private var newTodo = ""

    var body: some View {
        let b = store.binding(kind)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: kind.icon).font(.system(size: 22)).foregroundStyle(Color.accentColor)
                Text(kind.title).font(.system(size: 17, weight: .bold))
                Spacer()
                Toggle("", isOn: b.enabled).labelsHidden().toggleStyle(.switch)
            }
            if !b.wrappedValue.enabled {
                Text("Kapalı. Açınca masaüstünde görünür.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Panel(title: "Görünüm") {
                StyleChips(selection: b.style)
                LabeledSlider(title: "Boyut", value: b.scale, range: 0.5...1.8)
                LabeledSlider(title: "Opaklık", value: b.opacity, range: 0.2...1)
            }
            if interactiveKinds.contains(kind) {
                Panel(title: "Tıklanabilirlik", subtitle: "Açıkken bu widget simgelerin üstüne çıkar ve tıklamalara yanıt verir (düğmeler, onay kutuları). Kapalıyken simgelerin arkasında kalır ve tıklanamaz.") {
                    Toggle("Tıklanabilir olsun", isOn: b.clickable)
                }
            }
            options
        }
    }

    @ViewBuilder private var options: some View {
        switch kind {
        case .clock:
            Panel(title: "Saat") {
                Toggle("24 saat biçimi", isOn: $store.s.clock24h)
                Toggle("Saniyeyi göster", isOn: $store.s.showSeconds)
            }
        case .bigClock:
            Panel(title: "Saat") { Toggle("24 saat biçimi", isOn: $store.s.clock24h) }
        case .analog:
            Panel(title: "Analog saat") { Toggle("Saniye ibresi", isOn: $store.s.analogSeconds) }
        case .world:
            Panel(title: "Şehirler", subtitle: "En fazla 4 şehir") {
                ForEach(Array(store.s.worldZones.enumerated()), id: \.offset) { i, tz in
                    HStack {
                        Text(worldCities.first { $0.tz == tz }?.name ?? tz)
                        Spacer()
                        Button { store.s.worldZones.remove(at: i) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                if store.s.worldZones.count < 4 {
                    Menu("Şehir ekle") {
                        ForEach(worldCities.filter { c in !store.s.worldZones.contains(c.tz) }, id: \.tz) { c in
                            Button(c.name) { store.s.worldZones.append(c.tz) }
                        }
                    }
                }
            }
        case .weather, .sunmoon:
            Panel(title: "Konum", subtitle: "Hava durumu, doğuş ve batış bu şehre göre") {
                TextField("Şehir", text: $store.s.city, prompt: Text("Örn. Istanbul, Kardzhali"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { WidgetManager.shared.weather.load(city: store.s.city) }
                Text("Yazıp Enter'a basın.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .todo:
            Panel(title: "Görevler", subtitle: "Widget'taki daireye tıklayarak da işaretleyebilirsiniz (simgelerin üstünde modunda).") {
                ForEach($store.s.todos) { $t in
                    HStack {
                        Toggle("", isOn: $t.done).labelsHidden()
                        TextField("", text: $t.text).textFieldStyle(.roundedBorder)
                        Button { store.s.todos.removeAll { $0.id == t.id } } label: { Image(systemName: "trash").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Yeni görev…", text: $newTodo).textFieldStyle(.roundedBorder).onSubmit(addTodo)
                    Button("Ekle", action: addTodo).disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        case .countdown:
            Panel(title: "Geri sayım") {
                TextField("Başlık", text: $store.s.countdownTitle).textFieldStyle(.roundedBorder)
                DatePicker("Tarih", selection: $store.s.countdownDate, displayedComponents: .date)
            }
        case .finance:
            Panel(title: "Piyasa") { Toggle("Bitcoin ve Ethereum'u göster", isOn: $store.s.showCrypto) }
        case .pomodoro:
            Panel(title: "Süreler") {
                Stepper("Odak: \(store.s.pomodoroFocus) dk", value: $store.s.pomodoroFocus, in: 5...90, step: 5)
                Stepper("Mola: \(store.s.pomodoroBreak) dk", value: $store.s.pomodoroBreak, in: 1...30)
            }
        case .photo:
            Panel(title: "Fotoğraflar", subtitle: "\(PhotoFrame.files.count) fotoğraf seçili") {
                Button("Fotoğraf / klasör seç…") { PhotoFrame.pick() }
                LabeledSlider(title: "Geçiş", value: $store.s.photoInterval, range: 3...60, format: { "\(Int($0)) sn" })
            }
        case .note:
            Panel(title: "Not") { TextEditor(text: $store.s.noteText).frame(height: 90).font(.system(size: 13)) }
        case .nowPlaying:
            NowPlayingOptions(m: WidgetManager.shared.nowPlaying)
        case .agenda:
            AgendaOptions(m: WidgetManager.shared.agenda)
        default:
            EmptyView()
        }
    }

    private func addTodo() {
        let t = newTodo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.s.todos.append(Todo(text: t)); newTodo = ""
    }
}

// MARK: - Sayfa: Görünüm

struct LookPage: View {
    @ObservedObject private var store = Store.shared
    @State private var bulkStyle: CardStyle = .glass
    @State private var bulkOpacity = 1.0

    var body: some View {
        Text("Görünüm").font(.system(size: 26, weight: .bold))
        Panel(title: "Vurgu rengi", subtitle: "Saniye ibresi, halkalar, Aurora ve Neon gibi renkler buradan türetilir.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 10)], spacing: 10) {
                ForEach(0..<14, id: \.self) { i in
                    let h = Double(i) / 14
                    Button { store.s.accentHue = h } label: {
                        Circle().fill(Color(hue: h, saturation: 0.65, brightness: 1)).frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(abs(store.s.accentHue - h) < 0.04 ? Color.primary : .clear, lineWidth: 2.5).padding(-3))
                    }.buttonStyle(.plain)
                }
            }
            LabeledSlider(title: "İnce ayar", value: $store.s.accentHue, range: 0...1, format: { _ in "" })
        }
        Panel(title: "Hepsine stil uygula", subtitle: "Açık olan ve olmayan tüm widget'ların kart stilini değiştirir.") {
            StyleChips(selection: Binding(get: { bulkStyle }, set: { bulkStyle = $0; store.applyStyleToAll($0) }))
        }
        Panel(title: "Hepsinin opaklığı") {
            LabeledSlider(title: "Opaklık", value: Binding(get: { bulkOpacity }, set: { v in
                bulkOpacity = v
                for k in WidgetKind.allCases { var c = store.config(k); c.opacity = v; store.s.configs[k.rawValue] = c }
            }), range: 0.2...1)
        }
    }
}

// MARK: - Sayfa: Masaüstü

struct DesktopPage: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Text("Masaüstü").font(.system(size: 26, weight: .bold))
        Panel(title: "Simgelere göre konum", subtitle: "Masaüstündeki klasör ve dosyalarla çakışma sorununu burası çözer.") {
            ForEach(Placement.allCases) { pl in
                Button { store.s.placement = pl } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: store.s.placement == pl ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(store.s.placement == pl ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pl.title).font(.system(size: 13, weight: .medium))
                            Text(pl == .behind
                                 ? "Klasörler ve dosyalar widget'ların üstünde görünür. Widget'lara tıklanamaz (saat, hava gibi göstermelik olanlar için ideal)."
                                 : "Widget'lar simgelerin üstünde durur. Müzik, Pomodoro, Yapılacaklar gibi tıklanan widget'lar için.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }.buttonStyle(.plain)
            }
        }
        Panel(title: "Ekran") {
            Picker("Widget ekranı", selection: $store.s.screenIndex) {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, sc in
                    Text("\(i + 1). \(sc.localizedName)\(i == 0 ? "  ·  ana ekran (menü çubuğu burada)" : "")").tag(i)
                }
            }
            Text("Ekranı değiştirince bir set uygulayın veya konumları sıfırlayın.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Panel(title: "Konumlar") {
            Toggle("Konumları düzenle (sürükleyerek yerleştir)", isOn: $store.editing)
            Toggle("Konumları kilitle", isOn: $store.s.locked)
            HStack {
                Button("Düzenli diz") { WidgetManager.shared.autoArrangeCurrent() }
                Button("Konumları sıfırla") { WidgetManager.shared.resetPositions() }
            }
        }
        Panel(title: "Genel") {
            Toggle("Tüm widget'ları gizle", isOn: $store.allHidden)
            Toggle("Girişte başlat", isOn: $store.launchAtLogin)
        }
    }
}

// MARK: - Müzik ve ajanda ayar panelleri

struct NowPlayingOptions: View {
    @ObservedObject var m: NowPlayingModel
    var body: some View {
        Panel(title: "Durum") {
            if m.available {
                Label("\(m.title) · \(m.artist)", systemImage: m.playing ? "play.fill" : "pause.fill").font(.system(size: 12))
                Text("Kaynak: \(m.displayName)").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("Şu an çalan parça yok.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let n = m.note { Text(n).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Button("Yenile") { m.refresh() }
                Button("Otomasyon izni iste") { m.requestAutomationAccess() }
                Button("Ayarları aç") { m.openAutomationSettings() }
            }
        }
        Panel(title: "Nasıl çalışır", subtitle: "Parça adı, sanatçı ve kapak resmi Spotify/Müzik'in sistem bildirimlerinden otomatik gelir, izin gerekmez ve işlemciyi yormaz. Oynat, ileri, geri ve ilerleme çubuğu için macOS'un otomasyon izni gerekir: \"Otomasyon izni iste\"ye basın ve çıkan pencerede izin verin.") { EmptyView() }
    }
}

struct AgendaOptions: View {
    @ObservedObject var m: AgendaModel
    @ObservedObject private var store = Store.shared
    var body: some View {
        Panel(title: "Takvim erişimi") {
            switch m.access {
            case .granted:
                Label("İzin verildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
            case .denied:
                Label("Erişim kapalı", systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.system(size: 12))
                Text("Sistem Ayarları → Gizlilik ve Güvenlik → Takvimler → HavaliWidget'ı açın.").font(.system(size: 11)).foregroundStyle(.secondary)
            default:
                Label("İzin bekleniyor", systemImage: "hourglass").foregroundStyle(.orange).font(.system(size: 12))
            }
            HStack {
                Button("İzin iste") { m.requestAccess() }
                Button("Ayarları aç") { m.openSettings() }
                Button("Yenile") { m.refresh() }
            }
        }
        Panel(title: "Gösterilecekler") {
            Stepper("Önümüzdeki \(store.s.agendaDays) gün", value: $store.s.agendaDays, in: 1...14)
                .onChange(of: store.s.agendaDays) { _, _ in m.refresh() }
            if m.calendars.isEmpty {
                Text("Takvim listesi izin verilince burada görünür.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(m.calendars) { c in
                    Toggle(isOn: Binding(
                        get: { !store.s.hiddenCalendars.contains(c.id) },
                        set: { on in
                            if on { store.s.hiddenCalendars.removeAll { $0 == c.id } } else { store.s.hiddenCalendars.append(c.id) }
                            m.refresh()
                        })) {
                        HStack { Circle().fill(c.color).frame(width: 9, height: 9); Text(c.title).font(.system(size: 12)) }
                    }
                }
            }
        }
    }
}
