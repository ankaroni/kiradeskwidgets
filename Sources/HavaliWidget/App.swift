import SwiftUI

@main
struct HavaliWidgetApp: App {
    init() {
        DispatchQueue.main.async { WidgetManager.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra("HavaliWidget", systemImage: "square.grid.2x2.fill") {
            MenuContent()
        }
        Window("HavaliWidget Ayarları", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 940, height: 680)
    }
}

struct MenuContent: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(store.allHidden ? "Widget'ları Göster" : "Widget'ları Gizle") { store.allHidden.toggle() }
        Menu("Widget'lar") {
            ForEach(WidgetKind.allCases) { k in
                Toggle(isOn: Binding(
                    get: { store.config(k).enabled },
                    set: { var c = store.config(k); c.enabled = $0; store.s.configs[k.rawValue] = c })) {
                    Label(k.title, systemImage: k.icon)
                }
            }
        }
        Menu("Hazır setler (otomatik diz)") {
            ForEach(layoutSets) { set in
                Button { WidgetManager.shared.apply(set: set) } label: { Label(set.name, systemImage: set.icon) }
            }
        }
        Button("Açık widget'ları düzenli diz") { WidgetManager.shared.autoArrangeCurrent() }
        Menu("Hazır görünüm") {
            ForEach(CardStyle.allCases) { st in Button("Hepsi: \(st.title)") { store.applyStyleToAll(st) } }
        }
        Divider()
        Button("Ayarlar…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(store.editing ? "Düzenlemeyi Bitir ✓" : "Konumları Düzenle (sürükle)") { store.editing.toggle() }
        Menu("Masaüstü: \(store.s.placement == .behind ? "simgelerin arkasında" : "simgelerin üstünde")") {
            ForEach(Placement.allCases) { pl in
                Button((store.s.placement == pl ? "✓  " : "     ") + pl.title) { store.s.placement = pl }
            }
        }
        Toggle("Konumları kilitle", isOn: $store.s.locked)
        Button("Konumları Sıfırla") { WidgetManager.shared.resetPositions() }
        Divider()
        Button("Çıkış") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

