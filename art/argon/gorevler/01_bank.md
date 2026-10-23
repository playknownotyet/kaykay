# 01 — Sokak bankı

Durum: ONAY

**Kart adı (dosya ve nesne adı):** `bank`
**Ölçü (en x, derinlik y, yükseklik z):** 1,60 × 0,60 × 0,85 m
**Üçgen sınırı:** 700
**Kontrol çağrısı:** `kontrol("bank", ucgen_sinir=700, olcu=(1.6, 0.6, 0.85))`

## Ne
Sahil şehrinin meydanlarında ve kaldırımlarında duran, sırtlıklı iki kişilik park bankı.

## İstenenler
- Oturak üst yüzeyi tam **0,45 m** yükseklikte, düz ve en az 0,40 m derin (karakter oturacak).
- Oturak **önü −Y'de**; sırtlık +Y tarafında, hafif geriye yatık.
- 3–4 kalın ahşap çıta (oturak) + 2–3 çıta (sırtlık), aralarında belirgin boşluk.
- İki yanda kalın, biraz kıvrımlı metal ayak / kolçak (tek parça yan profil gibi). Ayaklar yere oturur.
- Oturma yerleri x = −0,40 ve +0,40 m civarında; kolçak bu iki yeri kapatmasın.

## Renk önerisi
Çıtalar ahşap `#c97b3a` (yanları `#8c5a3c`), yan ayaklar koyu yeşil `#2f7d6d` ya da turkuaz `#2aa198`.

## Oyundaki kullanımı
Adada 48 bank var; oyuncu ve hayvan NPC'ler oturuyor. Kaykayla çarpılır, üstüne çıkılabilir.

## Geri bildirim
Oyunda çok iyi duruyor (renkler, çıtalar, döküm ayaklar, rozetler aynen kalsın). Tek değişiklik kaykay için:
1. **Kolçakları kaldır.** Yan döküm ayaklar oturak yüksekliğinde (0,45 m) bitsin; arkada sırtlığı taşıyan
   dikme yükselebilir ama oturağın ön yarısında oturak üstüne çıkan hiçbir parça olmasın. Oyuncu oturağın
   ön kenarında baştan sona (x = −0,80 … +0,80) 50-50 yapacak ve bir banktan ötekine atlayacak.
2. Oturak çıtaları iki uçta x = ±0,80'e kadar uzasın, uçlar temiz bitsin.
3. Oturağın **ön kenarına** ince metal bir koruma şeridi ekle (koyu yeşil `#2f7d6d`, ~3 cm): kayılacak kenar
   belli olsun.
4. Hardal rozetler yan ayakta kalabilir. Ölçü, yönler ve üçgen sınırı aynı.

## Argon notu
ucgen: 560 · olcu: 1.60 x 0.60 x 0.85 m · Kolçaklar kaldırıldı, oturak x = ±0,80 kesintisiz, ön kenarda
~3 cm koyu yeşil koping, hardal rozetler ön ayak omzunda.

**Claude: ONAY** — oyuna alındı (assets/props/argon/bank.glb): sahil yolu, meydan ve adanın eski bank yerleri.
