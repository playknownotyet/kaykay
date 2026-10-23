# Kaykay — Argon için eşya modelleme rehberi

Merhaba Argon. Bu klasör "Kaykay" adlı mobil 3D kaykay oyununun şehir eşyalarını modellediğin yer.
Oyun Godot 4'te; sen Blender'da (Blender MCP üzerinden) modelliyorsun, oyuna yerleştirmeyi başka
bir ajan (Claude) yapıyor. Her oturumda **tek bir görev** yap, bu rehbere harfiyen uy.

## Her oturumda yapacakların

1. Bu dosyayı baştan sona oku. `referans/` klasöründeki görüntülere bak (aşağıda ne olduklarını anlattım).
2. Claude sana hangi kartı yapacağını söyler (`gorevler/NN_ad.md`). O kartı oku; `Geri bildirim`
   bölümü doluysa önce onları düzelt. **Kart dosyalarına sen yazma**: durumu ve notları Claude günceller.
3. Blender'da araçları yükle (execute_blender_code ile):
   ```python
   exec(open("/Users/kerem/Projects/kaykay/art/argon/araclar/kaykay_araclar.py").read())
   yeni_sahne("<kart_adi>")      # boş sahne + cikti/<kart_adi>/<kart_adi>.blend
   ```
   `yeni_sahne` açık sahnedeki her şeyi siler; kaydedilmemiş iş varsa önce kaydet.
4. Modeli **Python koduyla** kur. Adım adım ilerle, her adımdan sonra `look` ile bak:
   - **Kaba şekil (blockout):** yalnız ana hacimler, karttaki ölçülerle. Orantıları referanslarla karşılaştır.
   - **Biçim:** pahlar (1–2 segment), kalınlıklar, siluet. Ayrıntı ekledikçe üçgen sınırını izle.
   - **Renk:** `renk(obj, "#hex")` / `renk_yuz(obj, [yüz indeksleri], "#hex")`. Yalnız aşağıdaki paletten.
   - **Eleştiri turu (en az 2):** `look` ile önden 3/4 açıdan, yandan ve göz hizasından (1,6 m, 3–4 m uzaktan)
     bak. Kendine sor: "Bu, referanstaki şehrin içinde aynı oyunun parçası gibi duruyor mu? Uzaktan
     ve düşük çözünürlükte neye benzediği hemen anlaşılıyor mu?" Değilse düzelt.
5. `birlestir("<kart_adi>")` → `r = kontrol("<kart_adi>", ucgen_sinir=..., olcu=(en, derinlik, yükseklik))`.
   `r["gecti"]` False ise `r["sorunlar"]`ı düzelt, tekrar kontrol et.
6. `disa_aktar("<kart_adi>")`: GLB ve önizlemeleri `cikti/<kart_adi>/` içine yazar, .blend'i kaydeder.
7. `onizleme_*.png` görüntülerine bak. Beğenmediğin bir şey varsa düzelt ve tekrar dışa aktar.
8. Son cevabında şu bloğu yaz (Claude bunu karta işler), sonra dur:
   ```
   ARGON NOTU
   kart: <kart_adi>
   ucgen: <sayı>
   olcu: <en x derinlik x yükseklik m>
   kararlar: <kısa>
   emin_olmadiklarim: <kısa>
   ```

## Yasaklar

- **Hazır model kullanma.** Poly Haven, Sketchfab, Poly Pizza, Hyper3D, Hunyuan, Meshy, Tripo, Rodin
  gibi kütüphane / üretici araçlarının hiçbirini açma, `search_assets`, `import_asset`, `generate_3d` çağırma.
  Her şey sıfırdan, kodla modellenir.
- İnternetten hiçbir şey indirme. Resim dokusu (texture) kullanma.
- Bu klasörün (`art/argon/`) dışında hiçbir dosyaya yazma; Blender kodu da yalnız `cikti/<kart_adi>/` içine yazar.
  `araclar/`, `referans/` ve `gorevler/` içindekileri değiştirme.
- Bir oturumda tek kart. Bitince başka karta geçme.

## Sanat dili

Oyunun görünümü: **temiz, canlı renkli, yumuşak toon ışıklı low-poly**. Akdeniz kıyısında, renkli
cepheli, çizgili tenteli, güneşli bir sahil şehri. Oyun dünyayı düşük çözünürlükte (piksel piksel) çizer
ve üstüne hafif bir retro filtre koyar; bu yüzden:

- **Büyük, okunaklı biçimler.** 3 cm'den ince ayrıntılar görünmez; onların yerine biçimi abart.
  Siluet uzaktan bir bakışta ne olduğunu söylemeli.
- **Renk blokları.** Her parça tek, düz bir renk. Gölge / kir / yıpranma boyama yok. Doku yok.
- **Hafif sevimli orantılar:** biraz tombul, biraz yuvarlatılmış köşeler (1–2 segment pah), kalın kenarlar.
  Gerçekçi değil, oyuncak gibi ama ciddi bir şehir eşyası olduğu da anlaşılsın.
- **Doygun, temiz renkler.** Gri ve kahve kullanılabilir ama çamurlu değil; her eşyada en az bir canlı vurgu rengi.
- Düz yüz gölgelendirme (flat) yeterli; oyunun toon ışığı yüzleri basamaklı aydınlatır.
- **Saydamlık yok:** Oyunda cam yüzleri saydam değil, düz renkli yüzeydir. İçindekinin görünmesi gereken
  yerlere (vitrin, tezgâh, dolap içi) cam koyma; yalnız çerçeve bırak. Arkası boş durak camı gibi yerlerde
  cam rengi (gök mavisi) kullanılabilir.
- **Bitkiler** yuvarlak ve tombul: birbirine geçen iri ikosfer öbekleri (2 bölme), üstü açık `#6fbf4a`,
  altı koyu `#2f7d6d`. Köşeleri çekiştirilmiş sivri "kristal" biçimler olmasın.
- **Kesinlikle olmasın:** paslı, kirli, eskimiş, soluk, fotogerçekçi görünüm. `referans/eski_*.png`
  görüntüleri tam olarak bunun örneği; oyundan bu yüzden çıkarıldılar. Onların tersini yap.

### Referans görüntüler (`referans/`)

- `sehir_1.png` … `sehir_4.png`: oyun kamerasından şehir (karakter, meydan, binalar, tenteler).
  Renk ve biçim dili bu. Yeni eşyalar bu sahnelerin içinde doğal durmalı.
- `eski_*.png`: **kötü örnek.** Eskiden kullanılan gerçekçi, kirli modeller (bank, çöp kovası, lamba,
  yangın musluğu). Bunların yerine yenilerini yapıyoruz.

### Palet

Yalnız bu renkleri kullan (kartta özel renk istenirse o geçerli). Ana renk + bir vurgu + gerekiyorsa koyu ayrıntı.

| Ad | Hex | Kullanım |
| --- | --- | --- |
| Deniz mavisi | `#3f7fc4` | metal gövdeler, tabelalar |
| Gök mavisi | `#7cc3ec` | açık vurgular |
| Turkuaz | `#2aa198` | metal boya, park eşyası |
| Koyu yeşil | `#2f7d6d` | sokak mobilyası metali (bank ayağı, lamba direği) |
| Çimen yeşili | `#6fbf4a` | bitki, yaprak |
| Hardal | `#f2c14e` | vurgu, uyarı şeridi |
| Turuncu | `#f08a3c` | vurgu, koni |
| Mercan | `#f08f6c` | sıcak vurgu |
| Kırmızı | `#d9473f` | yangın musluğu, posta, uyarı |
| Pembe | `#f29bb5` | tente, süs |
| Krem | `#f3efe6` | açık yüzeyler, beton üstü |
| Kum | `#e2d6bf` | taş, beton |
| Ahşap | `#c97b3a` | ahşap çıta |
| Koyu ahşap | `#8c5a3c` | ahşap gölgeli yan |
| Antrasit | `#3a3a3a` | lastik, koyu metal ayrıntı (az kullan) |
| Gri | `#9a9a9a` | çelik, beton (az kullan) |
| Ampul sarısı | `#fff3c4` (alfa 0.3) | yanan lamba, ekran (parlayan yüz) |

**Parlayan yüzler:** `renk(obj, "#fff3c4", alfa=0.3)` — alfa 1'den küçük yüzler oyunda kendiliğinden parlar
(lamba camı, ekran, neon). Diğer bütün yüzler alfa 1.

**Gece:** Şehirde gece de var. Parlayan yüzler gündüz hafif, gece güçlü yanar; oyun lambaların altına
ayrıca ışık havuzu koyar. Bu yüzden gerçekte ışık veren her parçayı (fener camı, ampul, otomat ekranı,
durak tabelasının ışıklı yüzü, vitrin içi) parlayan yüz yap; ışık vermeyen hiçbir yüzü parlatma.
Fenerlerde camı, ampulün etrafını saran ve aşağı bakan geniş bir yüz olarak modelle (gece uzaktan seçilsin).

## Kaykayla etkileşim (en önemli kural)

Bu bir kaykay oyunu. Eşyalar şehrin doğal, gerçek eşyaları olarak durur (yapay rampa / demir değil),
ama oyuncu üstlerinde **50-50 / grind yapabilmeli, üstlerinden atlayabilmeli, birinden ötekine geçebilmeli**.
Şehirdeki gerçek kaykaycılar bankları, saksı kenarlarını, alçak duvarları nasıl kullanıyorsa öyle.

- **Grind kenarları:** Eşyanın üst kenarları (bank oturağının ön kenarı, saksının / duvarın üst kenarı,
  çeşme havuzunun ağzı) **düz, kesintisiz ve sağlam** olsun. Bu kenarlara ince metal ya da taş bir pervaz
  (koping) koyabilirsin; bakınca "burada kayılır" desin. Kart hangi kenarların grind kenarı olduğunu söyler.
- **Kaykay engeli yok:** Gerçek şehirlerdeki "skate stopper" çıkıntıları, ortada kolçak, kenarı bölen
  süsler yok. Kolçak gerekiyorsa yalnız en uçta ve oturaktan alçak.
- **Yükseklikler atlanabilir:** Üstünde kayılacak yüzeyler 0,30–0,55 m arası (kart verir). Bunun üstü
  ancak çift zıplamayla çıkılır.
- **Üst yüzeyler düz:** üstüne inilen yerler (oturak, duvar üstü, saksı kenarı) eğimsiz ve en az 0,25 m geniş.

## Teknik kurallar (oyuna doğrudan girebilmesi için)

- **Birim metre**, gerçek boyutlar (kartta yazar). Blender'da **Z yukarı**.
- **Ön yüz −Y'ye bakar** (Blender'ın "Front" görünümünde sana bakan taraf). Bank oturağı, tabelanın yazılı
  yüzü, otomatın ekranı −Y'de.
- **Tek mesh nesnesi**, adı kart adı (`birlestir` yapar). Konum (0,0,0), dönüş/ölçek uygulanmış.
- **Kök tabanın ortasında:** en alt nokta z = 0, x/y ortası 0 (`birlestir` yapar; zemine oturmayan
  çıkıntılar varsa tabanı yere değen kısım say).
- **Renkler köşe rengiyle** (`Col` katmanı; araçlar hazırlar). Malzeme / doku gerekmez.
- **Üçgen sınırı** kartta yazar; altında kal. Görünmeyen yüzleri (zemine oturan alt yüz) silebilirsin.
- Normaller dışa baksın (Shift+N). Üst üste binen gereksiz iç yüzler olmasın.
- Hareketli parça, kemik, animasyon yok (kartta istenmedikçe).

## Görev kartı biçimi

Kartlar `gorevler/NN_ad.md`. Durum satırını Claude yönetir: `BEKLIYOR` → `YAPILIYOR` → `INCELENIYOR` →
`ONAY` ya da `DUZELT`. `DUZELT` kartında Claude **Geri bildirim** bölümüne ne yapılacağını yazar; o kartı
tekrar aldığında aynı `.blend` dosyasını aç (`bpy.ops.wm.open_mainfile(filepath=...)`), düzelt, tekrar dışa aktar.

## Yapılacaklar listesi (ileride kart olacaklar)

Sokak: otobüs durağı, posta kutusu, gazete / dergi standı, bisiklet park demiri, trafik konisi, bariyer
dubası (bollard), büyük çöp konteyneri, içecek otomatı, simit arabası, kafe masası + sandalye + şemsiye,
sokak tabelası, parkmetre, elektrik dağıtım kutusu, yuvarlak çiçek saksısı, çeşme.
Çatılar: klima dış ünitesi, su deposu, anten, baca, güneş paneli.
Dükkân içleri (sonra): raflar, buzdolabı, kasa tezgâhı, ürün kutuları.
