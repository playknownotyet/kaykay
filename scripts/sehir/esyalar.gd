class_name Esyalar
extends Node3D
## Şehrin kaykaylanabilir sokak eşyaları (assets/ada/esyalar.json; tools/sehir/esya_yerlestir.gd üretir):
## sahil bankları, bahçe duvarları, oturak saksılar, çeşme, otobüs durakları, çöp kutuları.
## Modeller Argon'un yaptıkları (assets/props/argon/<tür>.glb); modeli olmayan tür atlanır.
## Her tür: 128 m parçalarda tek MultiMesh (tek çizim), basit çarpışma kutuları ve grind rayları.
## Uç uca duran eşyaların rayları (bahçe duvarı dizisi) tek uzun raya birleşir: kesintisiz kayılır.

const VERI := "res://assets/ada/esyalar.json"
const MODEL := "res://assets/props/argon/%s.glb"
const PROP_SCRIPT := preload("res://scripts/ada/prop_katmani.gd")
const CHUNK := 128.0

## Tür bilgisi (yerel: taban ortası, ön +Z, metre):
##  kutular: [merkez, boyut] çarpışma; raylar: [a, b] grind çizgileri; daire: [yarıçap, yükseklik, kenar]
##  yuzey: kaykay hissi; uzak: görünürlük mesafesi; oturak: bank oturma yerleri [x'ler, y, z, önde durma z]
const TURLER := {
	"bank": {
		"kutular": [[Vector3(0, 0.225, 0.04), Vector3(1.6, 0.45, 0.46)], [Vector3(0, 0.62, -0.24), Vector3(1.6, 0.46, 0.1)]],
		"raylar": [[Vector3(-0.78, 0.45, 0.25), Vector3(0.78, 0.45, 0.25)]],
		"yuzey": "tahta", "uzak": 170.0,
		"oturak": [[-0.4, 0.4], 0.45, 0.02, 0.75],
	},
	"tas_duvar": {
		"kutular": [[Vector3(0, 0.225, 0), Vector3(2.0, 0.45, 0.4)]],
		"raylar": [[Vector3(-1.0, 0.45, 0.17), Vector3(1.0, 0.45, 0.17)], [Vector3(-1.0, 0.45, -0.17), Vector3(1.0, 0.45, -0.17)]],
		"yuzey": "beton", "uzak": 160.0,
	},
	"oturak_saksi": {
		"kutular": [[Vector3(0, 0.25, 0), Vector3(2.6, 0.5, 0.9)]],
		"raylar": [[Vector3(-1.28, 0.5, 0.4), Vector3(1.28, 0.5, 0.4)], [Vector3(-1.28, 0.5, -0.4), Vector3(1.28, 0.5, -0.4)]],
		"yuzey": "beton", "uzak": 170.0,
	},
	"cesme": {
		"kutular": [[Vector3(0, 0.225, 0), Vector3(2.6, 0.45, 2.6)], [Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 0.7)]],
		"daire": [1.45, 0.45, 20],
		"yuzey": "beton", "uzak": 260.0,
	},
	"otobus_duragi": {
		# Argon modelinden ölçüldü: bank x −1,48…0,92 (ön kenar z −0,02), arka cam z −0,63, sol cam x −1,65,
		# çatı 2,45–2,60 m (ön kenarı z +0,74), sağda durak direği
		"kutular": [[Vector3(-0.28, 0.225, -0.23), Vector3(2.4, 0.45, 0.43)], [Vector3(-0.05, 1.3, -0.634), Vector3(3.4, 2.6, 0.1)],
			[Vector3(-1.65, 1.3, -0.13), Vector3(0.1, 2.6, 1.1)], [Vector3(-0.045, 2.525, -0.01), Vector3(3.5, 0.15, 1.49)],
			[Vector3(1.5, 1.2, 0.355), Vector3(0.18, 2.4, 0.18)]],
		"raylar": [[Vector3(-1.46, 0.45, -0.04), Vector3(0.9, 0.45, -0.04)], [Vector3(-1.75, 2.62, 0.7), Vector3(1.66, 2.62, 0.7)]],
		"yuzey": "metal", "uzak": 220.0,
		"oturak": [[-1.15, -0.28, 0.6], 0.45, -0.23, 0.4],
	},
	"cop_kutusu": {
		"silindir": [0.27, 0.95],
		"yuzey": "metal", "uzak": 150.0,
	},
	"saksi": {
		"kutular": [[Vector3(0, 0.215, 0), Vector3(0.93, 0.43, 0.43)]],
		"raylar": [[Vector3(-0.46, 0.43, 0.19), Vector3(0.46, 0.43, 0.19)], [Vector3(-0.46, 0.43, -0.19), Vector3(0.46, 0.43, -0.19)]],
		"yuzey": "beton", "uzak": 150.0,
	},
	"kafe_seti": {
		"kutular": [[Vector3(0, 0.375, 0), Vector3(0.7, 0.75, 0.7)], [Vector3(-0.62, 0.225, 0), Vector3(0.45, 0.45, 0.45)],
			[Vector3(0.62, 0.225, 0), Vector3(0.45, 0.45, 0.45)]],
		"yuzey": "metal", "uzak": 150.0,
	},
	"yuvarlak_saksi": {
		"silindir": [0.65, 0.45],
		"daire": [0.54, 0.45, 16],
		"yuzey": "beton", "uzak": 160.0,
	},
	"sezlong_semsiye": {
		"kutular": [[Vector3(-0.575, 0.18, 0), Vector3(0.65, 0.36, 1.9)], [Vector3(0.575, 0.18, 0), Vector3(0.65, 0.36, 1.9)]],
		"raylar": [[Vector3(-0.575, 0.36, -0.95), Vector3(-0.575, 0.36, 0.95)], [Vector3(0.575, 0.36, -0.95), Vector3(0.575, 0.36, 0.95)]],
		"yuzey": "tahta", "uzak": 180.0,
	},
	"simit_arabasi": {
		"kutular": [[Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 0.8)]],
		"yuzey": "metal", "uzak": 150.0,
	},
	"elektrik_kutusu": {
		"kutular": [[Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.4)]],
		"yuzey": "metal", "uzak": 140.0,
	},
	"cati_klima": {
		"kutular": [[Vector3(0, 0.4, 0), Vector3(1.1, 0.8, 0.7)]],
		"raylar": [[Vector3(-0.55, 0.8, 0.33), Vector3(0.55, 0.8, 0.33)], [Vector3(-0.55, 0.8, -0.33), Vector3(0.55, 0.8, -0.33)]],
		"yuzey": "metal", "uzak": 160.0,
	},
	"su_deposu": {
		"silindir": [0.58, 1.5],
		"yuzey": "metal", "uzak": 180.0,
	},
	"posta_kutusu": {
		"kutular": [[Vector3(0, 0.625, 0), Vector3(0.5, 1.25, 0.45)]],
		"yuzey": "metal", "uzak": 140.0,
	},
	"bufe": {
		"kutular": [[Vector3(0, 1.35, 0), Vector3(2.2, 2.7, 1.8)]],
		"raylar": [[Vector3(-1.05, 0.9, 0.9), Vector3(1.05, 0.9, 0.9)], [Vector3(-1.1, 2.72, 0.9), Vector3(1.1, 2.72, 0.9)]],
		"yuzey": "metal", "uzak": 220.0,
	},
	"trafik_konisi": {
		"silindir": [0.17, 0.6],
		"yuzey": "metal", "uzak": 110.0,
	},
	"cop_konteyneri": {
		"kutular": [[Vector3(0, 0.65, 0), Vector3(1.4, 1.3, 1.0)]],
		"raylar": [[Vector3(-0.68, 1.3, 0.48), Vector3(0.68, 1.3, 0.48)], [Vector3(-0.68, 1.3, -0.48), Vector3(0.68, 1.3, -0.48)]],
		"yuzey": "metal", "uzak": 150.0,
	},
	"icecek_otomati": {
		"kutular": [[Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.8)]],
		"yuzey": "metal", "uzak": 160.0,
	},
	"halat_babasi": {
		"silindir": [0.2, 0.55],
		"yuzey": "metal", "uzak": 120.0,
	},
	"balikci_kasasi": {
		"kutular": [[Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 0.8)]],
		"yuzey": "tahta", "uzak": 120.0,
	},
	"sandal": {
		"kutular": [[Vector3(0, 0.35, 0), Vector3(3.6, 0.7, 1.4)]],
		"raylar": [[Vector3(-1.6, 0.7, 0.72), Vector3(1.4, 0.7, 0.72)], [Vector3(-1.6, 0.7, -0.72), Vector3(1.4, 0.7, -0.72)]],
		"yuzey": "tahta", "uzak": 200.0,
	},
	"bisiklet": {
		"kutular": [[Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 0.25)]],
		"yuzey": "metal", "uzak": 120.0,
	},
	# Ahşap iskele modülleri: kökü kazık altında, döşeme üstü 2,5 m; boyu X (denize doğru +X)
	"iskele_modul": {
		"kutular": [[Vector3(0, 2.375, 0), Vector3(4.0, 0.25, 4.8)], [Vector3(0, 3.0, 2.3), Vector3(4.0, 1.0, 0.14)],
			[Vector3(0, 3.0, -2.3), Vector3(4.0, 1.0, 0.14)]],
		"yuzey": "tahta", "uzak": 260.0,
	},
	"iskele_uc": {
		"kutular": [[Vector3(0, 2.375, 0), Vector3(4.0, 0.25, 4.8)], [Vector3(0, 3.0, 2.3), Vector3(4.0, 1.0, 0.14)],
			[Vector3(0, 3.0, -2.3), Vector3(4.0, 1.0, 0.14)], [Vector3(1.95, 3.0, 1.6), Vector3(0.14, 1.0, 1.6)],
			[Vector3(1.95, 3.0, -1.6), Vector3(0.14, 1.0, 1.6)]],
		"yuzey": "tahta", "uzak": 260.0,
	},
	"kasa": {
		"kutular": [[Vector3(0, 0.13, 0), Vector3(0.5, 0.26, 0.4)]],
		"yuzey": "tahta", "uzak": 120.0,
	},
	"varil": {
		"silindir": [0.31, 0.93],
		"yuzey": "metal", "uzak": 160.0,
	},
	"yangin_muslugu": {
		"silindir": [0.15, 0.8],
		"yuzey": "metal", "uzak": 140.0,
	},
	"sokak_lambasi": {
		"silindir": [0.13, 3.8],
		"yuzey": "metal", "uzak": 300.0,
		"isik": Vector3(0, 2.9, 0.52),       # fener (ampul) yeri: gece ışığı buradan
		"kayma": Vector3(0, 0, 0.27),        # model kökü kutu ortasında; direk yerleşim noktasına gelsin
	},
}

## Adanın eski (Poly Haven) sokak eşyaları: Argon modeli gelen türün eski düğümleri kaldırılır, aynı
## yerlere yeni tür konur (assets/ada/ada.json street.props)
const ESKI := {
	"painted_wooden_bench": "bank", "metal_trash_can": "cop_kutusu", "street_lamp_01": "sokak_lambasi",
	"fire_hydrant": "yangin_muslugu", "planter_box_01": "saksi", "plastic_crate_02": "kasa", "barrel_03": "varil",
}

## Tür çeşitleri (assets/props/argon/<tür>_<çeşit>.glb; çarpışma / ray aynı türden). Eşya konumuna göre
## sabit seçilir: yan yana duranlar farklı renkte, her açılışta aynı
const CESITLER := {
	"saksi": ["2", "3"], "cop_kutusu": ["2"], "kafe_seti": ["2", "3"], "sezlong_semsiye": ["2"],
	"oturak_saksi": ["2"], "bank": ["metal"], "sokak_lambasi": ["cift"],
}
## Çeşide özel görsel ayarları (çarpışma ve raylar türden gelir)
const CESIT_AYAR := {
	# Direk ortada, iki yanda fener
	"sokak_lambasi_cift": {"kayma": Vector3.ZERO, "isiklar": [Vector3(-0.5, 3.05, 0), Vector3(0.5, 3.05, 0)]},
}

static var instance: Esyalar
var benches: Banklar
var level: Node
var player: Node3D
var lamps: LambaIsiklari
var items: Array = []


func _ready() -> void:
	instance = self
	if OS.get_environment("ESYALAR_KAPALI") == "1":    # performans karşılaştırması için
		return
	if FileAccess.file_exists(VERI):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VERI))
		items = d.get("items", [])
	_eskileri_degistir()
	_eski_iskeleler()
	_build()


func _eskileri_degistir() -> void:
	if level == null or not FileAccess.file_exists("res://assets/ada/ada.json"):
		return
	var yeni := {}
	for eski in ESKI:
		var t: String = ESKI[eski]
		if TURLER.has(t) and ResourceLoader.exists(MODEL % t):
			yeni[eski] = t
	if yeni.is_empty():
		return
	var ada: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/ada.json"))
	var yeni_iskele := ResourceLoader.exists(MODEL % "iskele_modul")
	for q in ada.get("street", {}).get("props", []):
		if not yeni.has(q.t):
			continue
		# Eski variller eski (geniş) iskelenin üstündeydi; yeni iskelede yerleştirici koyar
		if yeni_iskele and q.t == "barrel_03":
			continue
		# ada_builder ile aynı: konum (x, h, -y), -Z bakış yönü f; model önü +Z = -f
		var f := Vector3(float(q.f[0]), 0.0, -float(q.f[1])).normalized()
		items.append({"t": yeni[q.t], "p": [q.p[0], float(q.p[2]) - 0.02, -float(q.p[1])], "r": rad_to_deg(atan2(-f.x, -f.z)), "eski": true})
	for c in level.get_children():
		var nm := String(c.name)
		for eski in yeni:
			if nm.begins_with("Esya_" + eski) or nm.begins_with("EsyaCarpisma_" + eski):
				c.queue_free()
				# Çarpışma hemen kalksın (bu karede yeni gövdeler eklenecek)
				if c is CollisionObject3D:
					(c as CollisionObject3D).collision_layer = 0
	if yeni.has("painted_wooden_bench") and benches:
		benches.remove_tagged("")


## Adanın eski kutu iskeleleri: modüler iskele modeli varsa kaldırılır (yerine iskele_modul öğeleri)
func _eski_iskeleler() -> void:
	if level == null or not ResourceLoader.exists(MODEL % "iskele_modul"):
		return
	for c in level.get_children():
		if String(c.name).begins_with("Iskele_"):
			if c is CollisionObject3D:
				(c as CollisionObject3D).collision_layer = 0
			c.queue_free()


## Eşyanın model adı: türü ya da konumuna göre seçilen çeşidi (modeli varsa)
func _model_adi(t: String, pos: Vector3) -> String:
	var cs: Array = []
	for c in CESITLER.get(t, []):
		if ResourceLoader.exists(MODEL % (t + "_" + c)):
			cs.append(t + "_" + c)
	if cs.is_empty():
		return t
	var h := absi(int(floorf(pos.x * 7.31) * 73856093) ^ int(floorf(pos.z * 5.17) * 19349663))
	var k := h % (cs.size() + 1)
	return t if k == 0 else String(cs[k - 1])


func _build() -> void:
	var groups := {}
	var rails := []                       # [a, b, yüzey]
	var heads: Array[Vector3] = []        # gece ışıkları: lamba fenerleri ve altlarındaki zemin
	var grounds: Array[Vector3] = []
	for it in items:
		var t := String(it.t)
		if not TURLER.has(t) or not ResourceLoader.exists(MODEL % t):
			continue
		var spec: Dictionary = TURLER[t]
		var pos := Vector3(it.p[0], it.p[1], it.p[2])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(it.r))), pos)
		var model := _model_adi(t, pos)
		var key := "%s|%d|%d" % [model, floori(pos.x / CHUNK), floori(pos.z / CHUNK)]
		if not groups.has(key):
			groups[key] = {"t": t, "model": model, "items": []}
		var ayar: Dictionary = CESIT_AYAR.get(model, {})
		groups[key].items.append(xf * Transform3D(Basis(), ayar.get("kayma", spec.get("kayma", Vector3.ZERO))))
		var isiklar: Array = ayar.get("isiklar", [spec.isik] if spec.has("isik") else [])
		for li in isiklar:
			var hp: Vector3 = xf * (li as Vector3)
			heads.append(hp)
			grounds.append(Vector3(hp.x, pos.y, hp.z))
		if not groups[key].has("govde"):
			groups[key]["govde"] = []
		groups[key].govde.append(xf)
		for r in spec.get("raylar", []):
			rails.append([xf * (r[0] as Vector3), xf * (r[1] as Vector3), spec.yuzey])
		if spec.has("daire"):
			var dr: Array = spec.daire
			var n: int = dr[2]
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n
				rails.append([xf * Vector3(cos(a0) * dr[0], dr[1], sin(a0) * dr[0]), xf * Vector3(cos(a1) * dr[0], dr[1], sin(a1) * dr[0]), spec.yuzey])
		if spec.has("oturak") and benches:
			var o: Array = spec.oturak
			benches.add_bench(xf, "esya", o[0], o[1], o[2], o[3])
	for key in groups:
		_group(groups[key])
	for r in _merge(rails):
		var gr := GrindRail.new()
		add_child(gr)
		gr.setup(r[0], r[1], r[2])
	if not heads.is_empty():
		lamps = LambaIsiklari.new()
		lamps.name = "LambaIsiklari"
		lamps.player = player
		add_child(lamps)
		lamps.setup(heads, grounds)


func _group(g: Dictionary) -> void:
	var t: String = g.t
	var spec: Dictionary = TURLER[t]
	var tfs: Array = g.items
	var center := Vector3.ZERO
	for tf: Transform3D in tfs:
		center += tf.origin
	center /= tfs.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Esya_%s_%d" % [g.model, get_child_count()]
	mmi.position = center
	mmi.set_script(PROP_SCRIPT)
	mmi.set("model_path", MODEL % g.model)
	var rel: Array[Transform3D] = []
	for tf: Transform3D in tfs:
		rel.append(Transform3D(tf.basis, tf.origin - center))
	mmi.set("transforms", rel)
	mmi.visibility_range_end = spec.uzak
	add_child(mmi)
	var body := StaticBody3D.new()
	body.name = "EsyaGovde_%s" % t
	body.collision_layer = Sehir.LAYER
	body.collision_mask = 0
	body.set_meta("surface", spec.yuzey)
	add_child(body)
	for tf: Transform3D in g.govde:
		for k in spec.get("kutular", []):
			var sh := BoxShape3D.new()
			sh.size = k[1]
			var cs := CollisionShape3D.new()
			cs.shape = sh
			cs.transform = tf * Transform3D(Basis(), k[0])
			body.add_child(cs)
		if spec.has("silindir"):
			var sl: Array = spec.silindir
			var sh := CylinderShape3D.new()
			sh.radius = sl[0]
			sh.height = sl[1]
			var cs := CollisionShape3D.new()
			cs.shape = sh
			cs.transform = tf * Transform3D(Basis(), Vector3(0, sl[1] * 0.5, 0))
			body.add_child(cs)


## Uç uca, aynı doğrultudaki rayları birleştir (bahçe duvarı dizisi tek ray olur)
static func _merge(rails: Array) -> Array:
	var out := []
	var used := {}
	for i in rails.size():
		if used.has(i):
			continue
		used[i] = true
		var a: Vector3 = rails[i][0]
		var b: Vector3 = rails[i][1]
		var grew := true
		while grew:
			grew = false
			var dir := (b - a).normalized()
			for j in rails.size():
				if used.has(j):
					continue
				var c: Vector3 = rails[j][0]
				var d: Vector3 = rails[j][1]
				var dj := (d - c).normalized()
				if absf(dir.dot(dj)) < 0.995:
					continue
				if dir.dot(dj) < 0.0:
					var tmp := c
					c = d
					d = tmp
				if b.distance_to(c) < 0.12:
					b = d
				elif a.distance_to(d) < 0.12:
					a = c
				else:
					continue
				used[j] = true
				grew = true
		out.append([a, b, rails[i][2]])
	return out
