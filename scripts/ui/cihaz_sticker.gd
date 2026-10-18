class_name CihazSticker
## Cihaz çıkartmaları: modelin üstüne katman olarak yapıştırılan resimler (ileride aksesuar dükkânından
## alınıp oyuncunun seçtiği yerlere konacak). Model temiz kalır; çıkartma, yüzeyin çok az önünde
## duran ince bir dörtgendir (renkleri resimdekiyle birebir, kenarı saydam).
##
## Bir çıkartma: {tex: "res://...png", yuz: "on" | "arka", x, y (yüzey üstünde konum, m; o yüze
## bakana göre x sağ, y yukarı, kökü cihazın ortası), boyut (m, en), aci (derece, saat yönü tersine)}

## Müzik çalar: yüz düzlemleri (model, metre; tools/blender/muzikcalar_build.py: 62 x 104 x 11 mm)
const ON_Z := 0.0055
const ARKA_Z := -0.0055
const PAY := 0.00025            # yüzeyden ayrılma (titreşmesin)

## Şimdilik sabit: deneme çıkartması arka kapağın ortasında
const VARSAYILAN := [
	{"tex": "res://assets/stickerlar/civciv.png", "yuz": "arka", "x": 0.0, "y": 0.004, "boyut": 0.054, "aci": 0.0},
]


## Çıkartmaları cihaz düğümünün altına kur (öncekiler silinir)
static func apply(device: Node3D, list: Array) -> void:
	for c in device.get_children():
		if c.has_meta("sticker"):
			c.queue_free()
	for it in list:
		var tex: Texture2D = load(String(it.tex)) if ResourceLoader.exists(String(it.tex)) else null
		if tex == null:
			continue
		var s := float(it.get("boyut", 0.03))
		var q := QuadMesh.new()
		q.size = Vector2(s, s * tex.get_height() / maxf(tex.get_width(), 1.0))
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		# Baskı renkleri birebir (ışık ve ton eşleme soldurmasın)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.set_meta("sticker", true)
		var back := String(it.get("yuz", "arka")) == "arka"
		# Dörtgen +Z'ye bakar; arkadakiler Y etrafında yarım tur (arkadan bakınca düz okunur)
		var b := Basis(Vector3.UP, PI) if back else Basis()
		b = b * Basis(Vector3.BACK, deg_to_rad(float(it.get("aci", 0.0))))
		var x := float(it.get("x", 0.0))
		mi.transform = Transform3D(b, Vector3(-x if back else x, float(it.get("y", 0.0)), (ARKA_Z - PAY) if back else (ON_Z + PAY)))
		device.add_child(mi)
