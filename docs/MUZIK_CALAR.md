# Müzik çalar

Oyundaki cep müzik çaları iki kaynaktan çalar. Kaynak ve şarkı cihazın **MENU** düğmesinden seçilir:
parmağını tekerlekte çevirerek seçimi kaydır, **ortadaki düğmeyle** seç, **MENU** ile geri dön.

## Apple Music (yalnız iPhone)

Şarkıyı telefonun **Müzik** uygulaması çalar, oyun yönetir. Cihazı ilk açtığında iPhone Müzik izni
sorar: **İzin Ver**. (Reddettiysen: Ayarlar > Kaykay > Medya ve Apple Music.)

- **MENU > MÜZİK**: Çalma listeleri, Sanatçılar, Albümler, Şarkılar (tüm kütüphane), Hepsini karışık
  çal, Karışık açık / kapalı. Bir listeye girip şarkı seçince o şarkıdan başlayarak listeyi çalar;
  listenin başındaki **KARIŞIK ÇAL** listeyi karıştırarak çalar.
- Tekerlek: sağ sonraki, sol önceki (3 sn'den sonra başa sarar), alt oynat / durdur, orta tekrar
  (şarkıyı döngüye al). Sağ alttaki düğme cihazı kapatır (müzik durur).
- Kütüphanene eklediğin Apple Music şarkıları ve listeleri de görünür.
- Oyun sesi müziği kesmez (iOS ses oturumu "Ambient + karıştır").

## Oyun içi radyo (her yerde)

Oyunun kendi istasyonları, oyunun kendi sesiyle (iPhone, Android, bilgisayar). Şimdilik boş:
istasyonlar ve şarkılar `assets/radyo/radyo.json` dosyasına eklenecek. Biçim:

```json
{
	"istasyonlar": [
		{
			"ad": "KAYKAY FM",
			"sarkilar": [
				{ "dosya": "res://assets/radyo/kaykay_fm/parca1.ogg", "ad": "PARÇA ADI", "sanatci": "SANATÇI" }
			]
		}
	]
}
```

Şarkı dosyaları `.ogg`, `.mp3` ya da `.wav` olabilir (telifsiz / izinli parçalar). **MENU > RADYO**'dan
istasyon seçilir; tekerlek aynı şekilde çalışır (orta: şarkıyı tekrarla).

## Teknik

- Apple Music: `native/apple_muzik/` (GDExtension, Objective-C++, MediaPlayer). iOS iş akışında
  (`.github/workflows/ios-testflight.yml`) GitHub'ın Mac'inde derlenir; bilgisayarda yoktur.
- Oyun tarafı: `scripts/ui/muzik_servisi.gd` (kaynaklar, menüler), `muzik_calar.gd` (cihaz, tekerlek),
  `muzik_ekran.gd` (ekran).
- Spotify ve YouTube Music: iOS'ta herkese açık bir yolu olmadığı için çıkarıldı (Spotify'ın
  geliştirici erişimi 5 kişi ve Premium ile sınırlı; YouTube Music'in iOS için yönetme yolu yok).
