# iPhone'da test: Mac olmadan iOS kurulumu

Oyunu iPhone'una Mac olmadan yüklemek için derleme işini GitHub'ın Mac bilgisayarları yapar:

1. GitHub'da **Actions → iOS TestFlight → Run workflow** butonuna basarsın.
2. GitHub'ın Mac'i oyunu Godot ile Xcode projesine çevirir, derler, Apple imzanla imzalar.
3. Sonuç **TestFlight**'a yüklenir. iPhone'daki TestFlight uygulamasından tek dokunuşla kurarsın.

Bunun çalışması için Apple'dan birkaç dosya alıp GitHub'a **secret** (gizli değer) olarak eklemen gerekiyor.
Bunları **sadece sen** eklersin: şifreleri ve anahtarları kimseye (Claude dahil) yapıştırma.
İlk kurulum yaklaşık 30-45 dakika sürer, sonra her yeni sürüm tek tıklama.

---

## Maliyet (önemli)

- Depo **özel (private)** olduğu için GitHub, Mac dakikalarını **10 kat** sayar.
- Ücretsiz hesapta ayda 2.000 dakika var: bu yaklaşık **200 Mac dakikası** eder.
- Bir çalıştırma yaklaşık **10-15 dakika** sürer, yani ayda kabaca **12-15 derleme** yapabilirsin.
- Bu yüzden iş akışı kendiliğinden çalışmaz; sadece sen butona basınca çalışır.
- Kalan dakikanı görmek için: GitHub → sağ üstte profil resmin → **Settings → Billing and plans**.

---

## Adım 0 (önerilir): Secret'sız deneme

Apple işlerine girişmeden önce oyunun Mac'te derlenebildiğini görmek için:

1. https://github.com/playknownotyet/kaykay/actions → soldan **iOS TestFlight** → **Run workflow**.
2. **mod** kutusunda **`deneme`** seç → yeşil **Run workflow**.
3. Yeşil tik çıkarsa Godot → Xcode kısmı sorunsuz demektir. Kırmızıysa hatayı Claude'a göster.

Bu modda imza ve yükleme yapılmaz, hiçbir secret gerekmez (yine Mac dakikası harcar).

## Adım 1: Team ID'ni bul

1. https://developer.apple.com/account adresine gir.
2. **Membership details** (Üyelik ayrıntıları) bölümünde **Team ID** yazar (10 karakter, örn. `AB12CD34EF`).
3. Bunu bir yere not et. Secret adı: **`IOS_TEAM_ID`**.

## Adım 2: Uygulama kimliğini (Bundle ID) kaydet

1. https://developer.apple.com/account/resources/identifiers/list adresine gir.
2. Mavi **+** butonu → **App IDs** → Continue → **App** → Continue.
3. **Description:** `Kaykay`
4. **Bundle ID:** **Explicit** seç ve tam olarak şunu yaz: `com.playknownotyet.kaykay`
5. Capabilities listesinde hiçbir şeyi işaretleme → **Continue → Register**.

## Adım 3: App Store Connect'te uygulamayı oluştur

TestFlight'a yükleme yapabilmek için uygulamanın App Store Connect'te bir kaydı olmalı (yayınlanmaz, sadece kayıt).

1. https://appstoreconnect.apple.com/apps adresine gir.
2. **+** → **New App** (Yeni Uygulama).
3. **Platforms:** iOS
4. **Name:** App Store'da benzersiz olmalı. `Kaykay` alınmışsa `Kaykay Oyun` gibi bir şey yaz (sonra değiştirilebilir).
5. **Primary Language:** Turkish
6. **Bundle ID:** listeden `com.playknownotyet.kaykay` seç.
7. **SKU:** `kaykay`
8. **User Access:** Full Access → **Create**.

## Adım 4: Dağıtım sertifikası (Apple Distribution)

Normalde bu iş Mac ister; bunun için depoda bir yardımcı betik var: `tools/ios_sertifika.sh`.
Komutları **Git Bash** penceresinde çalıştır (Başlat menüsünde "Git Bash" yaz). Önce proje klasörüne gir:

```bash
cd /d/kaykay
```

**4a. İstek dosyası (CSR) oluştur:**

```bash
bash tools/ios_sertifika.sh csr
```

Bu, kullanıcı klasöründe `kaykay-ios-imza` adlı bir klasör açar ve içine `ios_dagitim.csr` koyar.
Aynı klasördeki `ios_dagitim.key` **özel anahtarındır**: kimseyle paylaşma, bir USB belleğe yedekle.

**4b. Apple'dan sertifikayı al:**

1. https://developer.apple.com/account/resources/certificates/list → **+**
2. **Apple Distribution** seç → Continue.
3. **Choose File** → `kaykay-ios-imza\ios_dagitim.csr` dosyasını seç → Continue.
4. **Download** → `distribution.cer` İndirilenler klasörüne iner.

**4c. .p12 dosyasını üret:**

```bash
bash tools/ios_sertifika.sh p12 ~/Downloads/distribution.cer
```

Senden bir şifre ister (yazarken ekranda görünmez, bu normal). Bu şifreyi unutma.
Betik `kaykay-ios-imza` klasörünü açar. Buradan iki secret çıkar:

- **`IOS_DIST_CERT_P12_BASE64`** → `IOS_DIST_CERT_P12_BASE64.txt` dosyasını Not Defteri ile aç, **tamamını** kopyala.
- **`IOS_DIST_CERT_PASSWORD`** → az önce belirlediğin şifre.

## Adım 5: Dağıtım profili (Provisioning Profile)

1. https://developer.apple.com/account/resources/profiles/list → **+**
2. **Distribution** başlığı altında **App Store Connect** seç → Continue.
3. App ID olarak **Kaykay (com.playknownotyet.kaykay)** seç → Continue.
4. Adım 4'te yaptığın sertifikayı seç → Continue.
5. **Provisioning Profile Name:** `Kaykay App Store` → **Generate** → **Download**.
6. Git Bash'te (dosya adı farklıysa ona göre düzelt):

```bash
bash tools/ios_sertifika.sh profil ~/Downloads/Kaykay_App_Store.mobileprovision
```

- **`IOS_PROVISIONING_PROFILE_BASE64`** → `IOS_PROVISIONING_PROFILE_BASE64.txt` dosyasının tamamı.

## Adım 6: App Store Connect API anahtarı

GitHub'ın Mac'i, oyunu TestFlight'a bu anahtarla yükler.

1. https://appstoreconnect.apple.com/access/integrations/api adresine gir
   (App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**).
2. İlk kez giriyorsan **Request Access** çıkabilir; onayla.
3. **Team Keys** sekmesi → **+** (Generate API Key).
4. **Name:** `GitHub`, **Access:** **App Manager** → **Generate**.
5. Listede yeni anahtarın satırında **Download** → `AuthKey_XXXXXXXXXX.p8` iner.
   **Dikkat: bu dosya sadece bir kez indirilebilir.** `kaykay-ios-imza` klasörüne taşı.
6. Üç secret çıkar:
   - **`ASC_KEY_ID`** → tablodaki **Key ID** (10 karakter).
   - **`ASC_ISSUER_ID`** → tablonun üstündeki **Issuer ID** (uzun, tireli; Copy butonu var).
   - **`ASC_KEY_P8`** → `.p8` dosyasını Not Defteri ile aç, `-----BEGIN PRIVATE KEY-----` satırından
     `-----END PRIVATE KEY-----` satırına kadar **tamamını** kopyala.

## Adım 7: Secret'ları GitHub'a ekle

1. https://github.com/playknownotyet/kaykay/settings/secrets/actions adresine gir
   (depo → **Settings** → **Secrets and variables** → **Actions**).
2. Her biri için **New repository secret** → **Name** kutusuna adı, **Secret** kutusuna değeri yapıştır → **Add secret**.

| Secret adı | Nereden |
|---|---|
| `IOS_TEAM_ID` | Adım 1 |
| `IOS_DIST_CERT_P12_BASE64` | Adım 4c, `.txt` dosyasının içeriği |
| `IOS_DIST_CERT_PASSWORD` | Adım 4c'de belirlediğin şifre |
| `IOS_PROVISIONING_PROFILE_BASE64` | Adım 5, `.txt` dosyasının içeriği |
| `ASC_KEY_ID` | Adım 6, Key ID |
| `ASC_ISSUER_ID` | Adım 6, Issuer ID |
| `ASC_KEY_P8` | Adım 6, `.p8` dosyasının içeriği |

Adlar büyük/küçük harf dahil **birebir** aynı olmalı. Toplam 7 secret.

## Adım 8: Derlemeyi başlat

1. https://github.com/playknownotyet/kaykay/actions adresine gir.
2. Soldan **iOS TestFlight** → sağda **Run workflow** → Branch: `main`, **mod:** `testflight` → yeşil **Run workflow**.
   (`ipa` modu imzalı dosyayı yapar ama yüklemez; sadece sorun ararken lazım olur.)
3. 10-15 dakika bekle. Yeşil tik = başarılı. Kırmızı çarpı = aşağıdaki "Sorun çıkarsa" bölümüne bak.

## Adım 9: iPhone'a kur

1. iPhone'a App Store'dan **TestFlight** uygulamasını indir (Apple'ın kendi uygulaması).
2. App Store Connect → **Apps** → Kaykay → **TestFlight** sekmesi.
3. Yüklenen derleme 5-30 dakika "Processing" (işleniyor) görünür, bekle.
4. Soldaki **Internal Testing** yanındaki **+** → grup adı `Ben` → kendi Apple hesabını test edici olarak ekle.
5. Derlemeyi bu gruba ekle. Telefonuna bir e-posta/bildirim gelir; TestFlight uygulamasında **Install**'a dokun.

Sonraki derlemeler aynı gruba otomatik düşer: sadece Adım 8'i tekrarla, sonra TestFlight'ta **Update**.

---

## Sorun çıkarsa

Actions sayfasında kırmızı çarpılı çalıştırmaya tıkla, kırmızı adımı aç; en alttaki satırlar hatayı söyler.

| Hata mesajı | Ne yapmalı |
|---|---|
| `Eksik GitHub secret'ları: ...` | Yazan secret'ları Adım 7'deki adlarla ekle. |
| `Sertifika (.p12) içe aktarılamadı` | Şifre yanlış ya da `.txt` içeriği eksik kopyalandı. İkisini yeniden ekle. |
| `Profil '...' için yapılmış, beklenen '...'` | `IOS_TEAM_ID` yanlış ya da profil başka App ID için. Adım 1 ve 5'i kontrol et. |
| `'App Store Connect' türünde dağıtım profili gerekli` | Adım 5'te **Development/Ad Hoc** değil **App Store Connect** seçilmeli. |
| `No signing certificate` / `doesn't include signing certificate` | Profil, Adım 4'teki sertifikayla yapılmamış. Profili yeniden oluşturup sertifikayı seç. |
| TestFlight adımında `Authentication failed` / `401` | `ASC_KEY_ID`, `ASC_ISSUER_ID` veya `ASC_KEY_P8` yanlış. |
| `No suitable application records were found` | Adım 3 yapılmamış ya da Bundle ID farklı seçilmiş. |
| `The bundle version must be higher` | Nadiren olur; iş akışını bir kez daha çalıştır (numara her seferinde artar). |

Takılırsan hata satırını Claude'a kopyala (secret değerlerini değil, sadece hata mesajını).

---

## Teknik notlar

- İş akışı dosyası: `.github/workflows/ios-testflight.yml`. Godot 4.7.2 ile Xcode projesi üretir, `xcodebuild` ile imzalayıp `.ipa` yapar, `altool` ile TestFlight'a yükler.
- Derleme numarası her çalıştırmada GitHub'ın çalıştırma numarasıdır (1, 2, 3...). Görünen sürüm `0.1`, `export_presets.cfg` içindeki `application/short_version` satırından değişir.
- `.ipa` dosyası her çalıştırmanın sayfasında 7 gün saklanır (Artifacts).
- Uygulama simgesi: `assets/icon_ios.png` (1024x1024, şeffaf olmamalı). Geçici bir simge; istediğin zaman değiştir.
- Sertifika 1 yıl, profil 1 yıl geçerlidir. Süre dolunca Adım 4-5'i tekrarla ve secret'ları güncelle.
