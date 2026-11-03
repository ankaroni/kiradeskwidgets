# KiraWidget

macOS için özgün, estetik masaüstü widget'ları (SwiftUI). Menü çubuğunda yaşar, widget'lar masaüstünde simgelerin arkasında durur.

## Widget'lar
Saat, Dev Saat (dikey), Analog Saat, Dünya Saati, Takvim, Ajanda (takvim etkinlikleri), Hava Durumu (saatlik grafik), Güneş ve Ay, Sistem (CPU/RAM/pil), Halkalar, Disk ve Ağ, Müzik Çalar (Spotify / Müzik), Yapılacaklar, Geri Sayım, Döviz ve Kripto, Pomodoro, Fotoğraf Çerçevesi, Günün Sözü, Not.

## Özellikler
- 8 kart stili: Cam, Koyu, Aurora, Neon, Pastel, Buzul, Gradyan, Şeffaf
- Hazır setler: tek tıkla widget seç, stil ver ve ekrana otomatik diz (ekrana göre ölçeklenir)
- Simgelerin arkasında / üstünde konum, widget başına tıklanabilirlik, sürükleyerek düzenleme modu
- Spotify/Müzik: izin gerektirmeden bildirimlerden çalan parça ve kapak; düğmeler için otomasyon izni
- Veri kaynakları anahtarsız: Open-Meteo (hava), open.er-api.com (döviz), CoinGecko (kripto)

## Derleme
```bash
./build_app.sh   # KiraWidget.app değil, HavaliWidget.app üretir
open HavaliWidget.app
```
Gereksinim: macOS 14+, Xcode komut satırı araçları (Swift 5.9+).

## Notlar
- Uygulama imzasızdır (ad-hoc). İzinlerin (Takvim, Otomasyon) yeniden derlemede kaybolmaması için imza gereksinimi sabit uygulama kimliğine bağlanır (`build_app.sh`).
- İlk açılışta engellenirse: sağ tık → Aç.
