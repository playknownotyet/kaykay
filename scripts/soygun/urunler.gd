class_name Urunler
## Market ürünleri: ad, arayüz rengi (ikon). Modeller assets/dukkan/dukkan.glb "urun_<ad>"
## (tools/blender/dukkan_build.py), ikonlar PixelArt.ICONS "<ad>".

const LIST := {
	"kola": {"ad": "Kola", "renk": Color(0.95, 0.3, 0.3)},
	"su": {"ad": "Su", "renk": Color(0.55, 0.8, 1.0)},
	"sut": {"ad": "Süt", "renk": Color(0.95, 0.97, 1.0)},
	"gevrek": {"ad": "Mısır gevreği", "renk": Color(1.0, 0.8, 0.25)},
	"cips": {"ad": "Cips", "renk": Color(1.0, 0.6, 0.2)},
	"cikolata": {"ad": "Çikolata", "renk": Color(0.75, 0.5, 0.9)},
	"bal": {"ad": "Bal", "renk": Color(1.0, 0.7, 0.2)},
	"ekmek": {"ad": "Ekmek", "renk": Color(0.9, 0.65, 0.35)},
	"elma": {"ad": "Elma", "renk": Color(1.0, 0.35, 0.3)},
	"kurabiye": {"ad": "Kurabiye", "renk": Color(0.85, 0.65, 0.4)},
	"macun": {"ad": "Diş macunu", "renk": Color(0.45, 0.65, 1.0)},
	"sampuan": {"ad": "Şampuan", "renk": Color(0.45, 0.9, 0.6)},
	"konserve": {"ad": "Konserve", "renk": Color(0.55, 0.85, 0.45)},
	"yumurta": {"ad": "Yumurta", "renk": Color(0.95, 0.92, 0.82)},
}


static func color(item: String) -> Color:
	return LIST[item].renk if LIST.has(item) else Color(1.0, 0.82, 0.25)


static func name_of(item: String) -> String:
	return LIST[item].ad if LIST.has(item) else item
