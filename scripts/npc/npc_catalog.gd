class_name NpcCatalog
extends RefCounted
## Hayvan NPC kataloğu: türler, kıyafet tercihleri, renk paletleri.
## Her türün kendi modeli var: assets/npc/<tür>.glb (tools/blender/npc_build.py <tür>).
## Model içindeki parça adları her türde aynıdır:
##   deri_govde, deri_kol_ust, deri_kol_alt   (kıyafetin açıkta bıraktığı deri)
##   tur_bas, tur_eller, [tur_kuyruk]          (türün kafası/boynu, elleri, kuyruğu)
##   ust_*, alt_*, ayk_*, sapka_*, aks_*        (o türün gövdesine biçilmiş kıyafetler)
##
## Her NPC: tür + üst + alt + ayakkabı (+ şapka, aksesuar) + renkler + boy/yapı.
## Türün zevkine uygun eşleşmeler ağırlıklıdır (zürafa takım elbiseli, fil işçi vb.)
## ama karışık kombinasyonlar da çıkar: yaşayan bir şehir hissi için.

# Tür:
#   skins: [ten, ten2, ten3] renk takımları (tüy/deri, açık bölgeler, desen/koyu bölgeler)
#   iris: göz rengi seçenekleri
#   height: boy çarpanı aralığı; build: yapı (en) çarpanı aralığı
#   anim_speed: modelin 1x yürüyüş animasyonundaki doğal hız (m/sn, npc_build çıktısı)
#   springs: yay kemikleri [kök, uç, sertlik, sönüm, yerçekimi] (kulak, kuyruk, hortum)
const SPECIES := {
	"zurafa": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.8, 0.5, 0.2), Color(0.96, 0.87, 0.66), Color(0.36, 0.2, 0.11)],
			[Color(0.72, 0.42, 0.18), Color(0.93, 0.84, 0.62), Color(0.3, 0.17, 0.1)],
			[Color(0.86, 0.58, 0.26), Color(0.98, 0.9, 0.72), Color(0.42, 0.24, 0.12)]],
		"iris": [Color(0.3, 0.17, 0.08), Color(0.22, 0.14, 0.1)],
		"height": Vector2(0.95, 1.05), "build": Vector2(0.94, 1.06), "anim_speed": 1.082, "weight": 0.8,
		"tops": {"ust_takim": 6, "ust_tisort": 1, "ust_kapusonlu": 1, "ust_isci": 1},
		"bottoms": {"alt_takim": 5, "alt_kot": 1, "alt_kargo": 1},
		"shoes": {"ayk_kundura": 5, "ayk_spor": 1},
		"hats": {"": 1},
		"acc": {"aks_evrak": 3, "": 2},
		"springs": [["ear.L.0", "ear.L.1", 2.2, 0.35, 0.2], ["ear.R.0", "ear.R.1", 2.2, 0.35, 0.2], ["tail.0", "tail.3", 0.9, 0.25, 0.6]],
	},
	"fil": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.56, 0.56, 0.6), Color(0.46, 0.46, 0.5), Color(0.68, 0.56, 0.57)],
			[Color(0.62, 0.58, 0.56), Color(0.52, 0.48, 0.47), Color(0.72, 0.58, 0.58)],
			[Color(0.48, 0.49, 0.52), Color(0.4, 0.4, 0.44), Color(0.66, 0.54, 0.56)]],
		"iris": [Color(0.42, 0.28, 0.14), Color(0.3, 0.2, 0.12)],
		"height": Vector2(0.96, 1.06), "build": Vector2(0.95, 1.1), "anim_speed": 0.722, "weight": 1.0,
		"tops": {"ust_isci": 5, "ust_tisort": 1, "ust_kapusonlu": 1, "ust_takim": 1},
		"bottoms": {"alt_kargo": 4, "alt_kot": 1, "alt_takim": 1},
		"shoes": {"ayk_bot": 5, "ayk_spor": 1},
		"hats": {"sapka_baret": 4, "sapka_kasket": 1, "": 1},
		"acc": {"": 1},
		"springs": [["trunk.0", "trunk.4", 0.8, 0.3, 0.5], ["ear.L.0", "ear.L.1", 1.2, 0.45, 0.3], ["ear.R.0", "ear.R.1", 1.2, 0.45, 0.3],
			["tail.0", "tail.2", 0.9, 0.25, 0.6]],
	},
	"penguen": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.12, 0.13, 0.16), Color(0.95, 0.94, 0.9), Color(0.98, 0.78, 0.2)],
			[Color(0.16, 0.18, 0.24), Color(0.96, 0.95, 0.92), Color(0.95, 0.6, 0.2)]],
		"iris": [Color(0.25, 0.12, 0.1), Color(0.15, 0.1, 0.1)],
		"height": Vector2(0.92, 1.06), "build": Vector2(0.95, 1.1), "anim_speed": 0.722, "weight": 1.2,
		"tops": {"ust_kapusonlu": 4, "ust_tisort": 2, "ust_kisa": 1, "ust_takim": 1},
		"bottoms": {"alt_kargo": 3, "alt_kot": 2},
		"shoes": {"ayk_spor": 3, "ayk_bot": 1},
		"hats": {"sapka_kasket": 3, "sapka_bere": 1, "": 2},
		"acc": {"": 3, "aks_omuz": 1},
		"springs": [["tail.0", "tail.1", 2.5, 0.4, 0.1]],
	},
	"guvercin": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.52, 0.56, 0.66), Color(0.36, 0.55, 0.45), Color(0.5, 0.36, 0.56)],
			[Color(0.42, 0.44, 0.5), Color(0.3, 0.5, 0.42), Color(0.45, 0.32, 0.5)],
			[Color(0.7, 0.69, 0.7), Color(0.4, 0.58, 0.5), Color(0.55, 0.42, 0.58)],
			[Color(0.5, 0.4, 0.36), Color(0.38, 0.52, 0.42), Color(0.5, 0.36, 0.5)]],
		"iris": [Color(0.95, 0.5, 0.1), Color(0.9, 0.35, 0.1)],
		"height": Vector2(0.94, 1.05), "build": Vector2(0.94, 1.08), "anim_speed": 0.75, "weight": 1.0,
		"tops": {"ust_kisa": 4, "ust_kapusonlu": 1, "ust_tisort": 1, "ust_takim": 1},
		"bottoms": {"alt_kargo": 3, "alt_kot": 2, "alt_takim": 1},
		"shoes": {"ayk_spor": 3, "ayk_bot": 1},
		"hats": {"": 3, "sapka_bere": 1, "sapka_kasket": 1},
		"acc": {"aks_omuz": 3, "": 1},
		"springs": [["tail.0", "tail.1", 2.0, 0.4, 0.1]],
	},
	"kedi": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.86, 0.55, 0.26), Color(0.97, 0.92, 0.84), Color(0.6, 0.32, 0.12)],
			[Color(0.55, 0.55, 0.58), Color(0.92, 0.92, 0.9), Color(0.32, 0.32, 0.35)],
			[Color(0.14, 0.13, 0.15), Color(0.88, 0.87, 0.85), Color(0.22, 0.21, 0.23)],
			[Color(0.9, 0.82, 0.68), Color(0.98, 0.96, 0.92), Color(0.78, 0.66, 0.5)],
			[Color(0.95, 0.94, 0.92), Color(0.98, 0.97, 0.95), Color(0.6, 0.5, 0.4)]],
		"iris": [Color(0.55, 0.78, 0.25), Color(0.85, 0.7, 0.2), Color(0.35, 0.6, 0.85)],
		"height": Vector2(0.93, 1.06), "build": Vector2(0.92, 1.06), "anim_speed": 1.077, "weight": 1.2,
		"tops": {"ust_tisort": 3, "ust_kapusonlu": 2, "ust_kisa": 2, "ust_takim": 1},
		"bottoms": {"alt_kot": 3, "alt_kargo": 1, "alt_takim": 1},
		"shoes": {"ayk_spor": 3, "ayk_kundura": 1},
		"hats": {"": 2, "sapka_bere": 1, "sapka_kasket": 1},
		"acc": {"": 2, "aks_omuz": 1},
		"springs": [["tail.0", "tail.4", 0.7, 0.25, 0.25], ["ear.L.0", "ear.L.1", 3.0, 0.5, 0.0], ["ear.R.0", "ear.R.1", 3.0, 0.5, 0.0]],
	},
	"kopek": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.66, 0.46, 0.28), Color(0.93, 0.86, 0.74), Color(0.4, 0.26, 0.15)],
			[Color(0.88, 0.68, 0.38), Color(0.97, 0.9, 0.78), Color(0.7, 0.5, 0.26)],
			[Color(0.18, 0.17, 0.17), Color(0.82, 0.66, 0.46), Color(0.1, 0.1, 0.1)],
			[Color(0.94, 0.92, 0.88), Color(0.98, 0.97, 0.95), Color(0.55, 0.4, 0.3)],
			[Color(0.6, 0.6, 0.62), Color(0.92, 0.92, 0.9), Color(0.35, 0.35, 0.38)]],
		"iris": [Color(0.42, 0.24, 0.1), Color(0.3, 0.18, 0.08), Color(0.45, 0.6, 0.8)],
		"height": Vector2(0.93, 1.07), "build": Vector2(0.94, 1.08), "anim_speed": 1.27, "weight": 1.3,
		"tops": {"ust_kapusonlu": 3, "ust_tisort": 3, "ust_isci": 1, "ust_takim": 1},
		"bottoms": {"alt_kot": 3, "alt_kargo": 2, "alt_takim": 1},
		"shoes": {"ayk_spor": 3, "ayk_bot": 1},
		"hats": {"sapka_kasket": 2, "": 2, "sapka_bere": 1},
		"acc": {"": 2, "aks_omuz": 1},
		"springs": [["ear.L.0", "ear.L.1", 0.9, 0.3, 0.8], ["ear.R.0", "ear.R.1", 0.9, 0.3, 0.8], ["tail.0", "tail.2", 1.6, 0.3, 0.1]],
	},
	"tavsan": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.8, 0.78, 0.76), Color(0.97, 0.96, 0.94), Color(0.62, 0.56, 0.52)],
			[Color(0.96, 0.95, 0.93), Color(0.99, 0.98, 0.97), Color(0.82, 0.78, 0.76)],
			[Color(0.6, 0.46, 0.33), Color(0.93, 0.88, 0.8), Color(0.42, 0.32, 0.24)],
			[Color(0.55, 0.55, 0.56), Color(0.9, 0.9, 0.9), Color(0.38, 0.38, 0.4)]],
		"iris": [Color(0.3, 0.18, 0.12), Color(0.15, 0.1, 0.1), Color(0.7, 0.2, 0.25)],
		"height": Vector2(0.92, 1.05), "build": Vector2(0.94, 1.06), "anim_speed": 1.03, "weight": 1.0,
		"tops": {"ust_kisa": 3, "ust_tisort": 2, "ust_kapusonlu": 2},
		"bottoms": {"alt_kot": 2, "alt_kargo": 2},
		"shoes": {"ayk_spor": 1},
		"hats": {"": 3, "sapka_bere": 1},
		"acc": {"aks_omuz": 2, "": 2},
		"springs": [["ear.L.0", "ear.L.2", 1.4, 0.3, 0.15], ["ear.R.0", "ear.R.2", 1.4, 0.3, 0.15]],
	},
	"sican": {
		"parts": ["tur_bas", "tur_eller", "tur_kuyruk"],
		"skins": [[Color(0.56, 0.52, 0.5), Color(0.82, 0.78, 0.74), Color(0.88, 0.6, 0.6)],
			[Color(0.38, 0.36, 0.35), Color(0.7, 0.66, 0.63), Color(0.85, 0.58, 0.58)],
			[Color(0.75, 0.72, 0.68), Color(0.92, 0.9, 0.86), Color(0.9, 0.62, 0.62)]],
		"iris": [Color(0.08, 0.06, 0.06)],
		"height": Vector2(0.93, 1.05), "build": Vector2(0.94, 1.06), "anim_speed": 0.97, "weight": 1.2,
		"tops": {"ust_kapusonlu": 4, "ust_tisort": 2, "ust_takim": 1, "ust_isci": 1},
		"bottoms": {"alt_kot": 3, "alt_kargo": 2, "alt_takim": 1},
		"shoes": {"ayk_spor": 3, "ayk_bot": 1},
		"hats": {"sapka_bere": 3, "sapka_kasket": 2, "": 1},
		"acc": {"": 1},
		"springs": [["tail.0", "tail.4", 0.6, 0.2, 0.7], ["ear.L.0", "ear.L.1", 2.5, 0.4, 0.1], ["ear.R.0", "ear.R.1", 2.5, 0.4, 0.1]],
	},
	"kurbaga": {
		"parts": ["tur_bas", "tur_eller"],
		"skins": [[Color(0.42, 0.66, 0.3), Color(0.9, 0.88, 0.6), Color(0.22, 0.4, 0.18)],
			[Color(0.3, 0.55, 0.38), Color(0.86, 0.88, 0.64), Color(0.16, 0.32, 0.2)],
			[Color(0.6, 0.72, 0.28), Color(0.92, 0.9, 0.66), Color(0.35, 0.45, 0.15)]],
		"iris": [Color(0.9, 0.7, 0.15), Color(0.85, 0.45, 0.12)],
		"height": Vector2(0.92, 1.05), "build": Vector2(0.95, 1.1), "anim_speed": 0.917, "weight": 0.9,
		"tops": {"ust_tisort": 2, "ust_kapusonlu": 2, "ust_isci": 2},
		"bottoms": {"alt_kot": 2, "alt_kargo": 2},
		"shoes": {"ayk_spor": 2, "ayk_bot": 1},
		"hats": {"": 1},
		"acc": {"": 1},
		"springs": [],
	},
}

# Üst kıyafetin tamamen örttüğü deri parçaları (içten taşma olmasın diye gizlenir)
const TOP_HIDES := {
	"ust_takim": ["deri_govde", "deri_kol_ust", "deri_kol_alt"],
	"ust_kapusonlu": ["deri_govde", "deri_kol_ust", "deri_kol_alt"],
	"ust_isci": ["deri_govde", "deri_kol_ust"],
	"ust_kisa": ["deri_kol_ust", "deri_kol_alt"],
	"ust_tisort": ["deri_govde"],
}

# Renk paletleri (sRGB). Anahtar: malzeme yuvası veya "yuva:parça"
const COLORS := {
	"kumas_ust:ust_takim": [Color(0.12, 0.14, 0.22), Color(0.18, 0.18, 0.2), Color(0.3, 0.22, 0.16), Color(0.4, 0.4, 0.43), Color(0.08, 0.08, 0.1)],
	"kumas_ust:ust_kapusonlu": [Color(0.18, 0.45, 0.38), Color(0.3, 0.4, 0.22), Color(0.6, 0.15, 0.15), Color(0.85, 0.7, 0.2),
		Color(0.45, 0.3, 0.6), Color(0.5, 0.5, 0.52), Color(0.15, 0.2, 0.35), Color(0.85, 0.45, 0.15)],
	"kumas_ust:ust_isci": [Color(0.22, 0.3, 0.5), Color(0.3, 0.4, 0.55), Color(0.35, 0.33, 0.3)],
	"kumas_ust:ust_kisa": [Color(0.55, 0.4, 0.75), Color(0.85, 0.5, 0.6), Color(0.25, 0.6, 0.6), Color(0.8, 0.65, 0.25), Color(0.3, 0.4, 0.6)],
	"kumas_ust:ust_tisort": [Color(0.92, 0.9, 0.86), Color(0.12, 0.12, 0.13), Color(0.7, 0.18, 0.18), Color(0.25, 0.4, 0.7),
		Color(0.9, 0.78, 0.3), Color(0.35, 0.6, 0.35), Color(0.9, 0.6, 0.7)],
	"kumas_ic:ust_takim": [Color(0.95, 0.95, 0.93), Color(0.75, 0.85, 0.95)],
	"kumas_ic": [Color(0.94, 0.92, 0.88), Color(0.95, 0.9, 0.78), Color(0.75, 0.75, 0.77), Color(0.15, 0.15, 0.16)],
	"kumas_alt:alt_kargo": [Color(0.5, 0.5, 0.3), Color(0.65, 0.58, 0.4), Color(0.4, 0.33, 0.25), Color(0.28, 0.3, 0.32), Color(0.75, 0.7, 0.55)],
	"kumas_alt:alt_kot": [Color(0.18, 0.24, 0.38), Color(0.28, 0.38, 0.58), Color(0.5, 0.6, 0.75), Color(0.15, 0.15, 0.17)],
	"kumas_alt:alt_takim": [Color(0.12, 0.14, 0.22), Color(0.18, 0.18, 0.2), Color(0.3, 0.22, 0.16), Color(0.4, 0.4, 0.43)],
	"ayakkabi:ayk_spor": [Color(0.9, 0.9, 0.9), Color(0.12, 0.12, 0.14), Color(0.35, 0.4, 0.55), Color(0.7, 0.2, 0.2), Color(0.2, 0.25, 0.4)],
	"ayakkabi:ayk_bot": [Color(0.45, 0.3, 0.18), Color(0.6, 0.45, 0.28), Color(0.3, 0.22, 0.15)],
	"ayakkabi:ayk_kundura": [Color(0.08, 0.08, 0.09), Color(0.25, 0.15, 0.1)],
	"ayakkabi_taban:ayk_spor": [Color(0.94, 0.93, 0.9), Color(0.78, 0.6, 0.4)],
	"ayakkabi_taban:ayk_bot": [Color(0.2, 0.17, 0.15)],
	"sapka:sapka_kasket": [Color(0.6, 0.15, 0.15), Color(0.15, 0.2, 0.35), Color(0.12, 0.12, 0.13), Color(0.3, 0.5, 0.3), Color(0.9, 0.9, 0.88)],
	"sapka:sapka_baret": [Color(0.95, 0.8, 0.15), Color(0.95, 0.95, 0.92), Color(0.95, 0.5, 0.15)],
	"sapka:sapka_bere": [Color(0.8, 0.65, 0.25), Color(0.5, 0.5, 0.52), Color(0.5, 0.15, 0.2), Color(0.2, 0.5, 0.5), Color(0.12, 0.12, 0.13)],
	"kravat": [Color(0.6, 0.1, 0.12), Color(0.15, 0.2, 0.4), Color(0.2, 0.4, 0.25), Color(0.75, 0.6, 0.2)],
	"aksesuar:aks_evrak": [Color(0.1, 0.09, 0.08), Color(0.3, 0.2, 0.12)],
	"aksesuar:aks_omuz": [Color(0.85, 0.78, 0.65), Color(0.12, 0.12, 0.13), Color(0.45, 0.45, 0.3)],
	"aksesuar:ust_isci": [Color(0.3, 0.22, 0.15)],
	"aksesuar": [Color(0.2, 0.15, 0.1), Color(0.1, 0.1, 0.1)],
	"yelek": [Color(0.95, 0.45, 0.1), Color(0.78, 0.92, 0.2)],
	"serit": [Color(0.85, 0.85, 0.8)],
	"tasma": [Color(0.75, 0.15, 0.12), Color(0.15, 0.3, 0.65), Color(0.2, 0.5, 0.25), Color(0.1, 0.1, 0.1)],
}


static func pick_weighted(rng: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]


static func pick_species(rng: RandomNumberGenerator) -> String:
	var table := {}
	for k in SPECIES:
		table[k] = SPECIES[k].weight
	return pick_weighted(rng, table)


## Bir NPC için kıyafet + renk + boy tarifi üretir.
static func make_recipe(rng: RandomNumberGenerator, species: String) -> Dictionary:
	var sp: Dictionary = SPECIES[species]
	var top := pick_weighted(rng, sp.tops)
	var bottom := pick_weighted(rng, sp.bottoms)
	var shoes := pick_weighted(rng, sp.shoes)
	# Takım elbise çoğunlukla takım pantolon + kundura ile, işçi gömleği botla
	if top == "ust_takim" and rng.randf() < 0.8:
		bottom = "alt_takim"
		shoes = "ayk_kundura"
	if top == "ust_isci" and rng.randf() < 0.7:
		shoes = "ayk_bot"
	var hat := pick_weighted(rng, sp.hats)
	if top == "ust_isci" and hat != "" and rng.randf() < 0.6 and sp.hats.has("sapka_baret"):
		hat = "sapka_baret"
	var acc := pick_weighted(rng, sp.acc)
	if acc == "aks_evrak" and top != "ust_takim":
		acc = ""

	var parts: Array = [top, bottom, shoes]
	parts.append_array(sp.parts)
	var hides: Array = TOP_HIDES.get(top, [])
	for skin_part in ["deri_govde", "deri_kol_ust", "deri_kol_alt"]:
		if not hides.has(skin_part):
			parts.append(skin_part)
	if hat != "":
		parts.append(hat)
	if acc != "":
		parts.append(acc)

	var skin: Array = sp.skins[rng.randi() % sp.skins.size()]
	var colors := {"ten": skin[0], "ten2": skin[1], "ten3": skin[2]}
	var irises: Array = sp.iris
	colors["iris"] = irises[rng.randi() % irises.size()]
	var pick := func(key: String) -> Color:
		var list: Array = COLORS[key]
		return list[rng.randi() % list.size()]
	colors["kumas_ust"] = pick.call("kumas_ust:" + top)
	colors["kumas_ic"] = pick.call("kumas_ic:" + top) if COLORS.has("kumas_ic:" + top) else pick.call("kumas_ic")
	colors["kumas_alt"] = pick.call("kumas_alt:" + bottom)
	if top == "ust_takim" and bottom == "alt_takim":
		colors["kumas_alt"] = colors["kumas_ust"]   # takım: ceket ve pantolon aynı renk
	colors["ayakkabi"] = pick.call("ayakkabi:" + shoes)
	colors["ayakkabi_taban"] = pick.call("ayakkabi_taban:" + shoes) if COLORS.has("ayakkabi_taban:" + shoes) else Color(0.92, 0.91, 0.88)
	if hat != "":
		colors["sapka"] = pick.call("sapka:" + hat)
	colors["kravat"] = pick.call("kravat")
	colors["yelek"] = pick.call("yelek")
	colors["serit"] = pick.call("serit")
	colors["tasma"] = pick.call("tasma")
	var acc_key := "aksesuar:" + (acc if acc != "" else top)
	colors["aksesuar"] = pick.call(acc_key) if COLORS.has(acc_key) else pick.call("aksesuar")

	# Boy ve yapı: aynı türün iki NPC'si bile farklı görünsün
	var h := rng.randf_range(sp.height.x, sp.height.y)
	var b := rng.randf_range(sp.build.x, sp.build.y)
	return {
		"species": species,
		"parts": parts,
		"colors": colors,
		"scale": Vector3(h * b, h, h * b),
		"anim_speed": float(sp.anim_speed) * h,
		"speed": float(sp.anim_speed) * h * rng.randf_range(0.88, 1.12),
		"springs": sp.springs,
	}
