class_name CepheEsyalari
extends Node3D
## Girilemez binaların cephelerinde daireden daireye değişen küçük farklar (Sehir.cephe_slots okunur):
##  - Pencerelerde perde / jaluzi (kodla, köşe renkli düz yüzler; gece hafif ışır)
##  - Pencerelerin bir kısmında çiçek kutusu, balkonların bir kısmında saksılar / çamaşır ipi / masa
##  - Bina kapılarında kapı modeli (renk çeşitli), önünde basamak, yanında duvar lambası (gece yanar)
## Seçimler bina kimliği + bölme + kattan sabit: her açılışta aynı daire aynı görünür.
## Modeller Argon / Flash (assets/props/argon); modeli olmayan eşya atlanır. Şehir yeniden kurulunca yenilenir.

const MODEL := "res://assets/props/argon/%s.glb"
const PROP_SCRIPT := preload("res://scripts/ada/prop_katmani.gd")
const VC_SHADER := preload("res://shaders/toon_vc.gdshader")
const SALLA_SHADER := preload("res://shaders/toon_vc_salla.gdshader")
const CHUNK := 128.0
const YOGUNLUK := 0.25            # pencerelerin / balkonların eşyalı oranı
const PERDE_ORAN := 0.55          # perdeli pencere oranı
const KAPILAR := ["kapi_ahsap", "kapi_ahsap_2", "kapi_ahsap_3", "kapi_camli", "kapi_camli_2", "kapi_camli_3"]
const BALKON := ["balkon_saksilari", "camasir_ipi", "balkon_masa"]
## Duvara yaslanan modellerin derinliğinin yarısı (arka yüz duvara otursun)
const DERINLIK := {"kapi_ahsap": 0.15, "kapi_camli": 0.15, "kapi_basamagi": 0.3, "duvar_lambasi": 0.2,
	"cicek_kutusu": 0.14, "balkon_saksilari": 0.2, "camasir_ipi": 0.15, "balkon_masa": 0.35}
const PERDE_RENK := ["#f3efe6", "#f29bb5", "#7cc3ec", "#f2c14e", "#f08f6c", "#2aa198", "#e2d6bf", "#d9473f"]

var city: Sehir
var _root: Node3D


func _ready() -> void:
	if city:
		city.rebuilt.connect(_rebuild)
		_rebuild()


static func _h(a: int, b: int, c: int, d: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 2654435761)
	x = (x ^ (x >> 13)) * 1274126177
	return float(absi(x) % 100000) / 100000.0


func _rebuild() -> void:
	if _root:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "CepheEsyalari"
	add_child(_root)
	var cephe: Dictionary = Sehir._cephe_data()
	var groups := {}                   # model|parça -> [Transform3D]
	var perdeler := {}                 # parça -> SurfaceTool
	for sl in city.cephe_slots:
		var cf: Transform3D = sl.cf
		var cw: float = sl.cw
		var row: int = sl.row
		var id: int = sl.id
		var mx := cw / 32.0
		var my := Sehir.KAT / 32.0
		var key := Vector2i(floori(cf.origin.x / CHUNK), floori(cf.origin.z / CHUNK))
		if row == 2:
			# Kapı: ortada; önünde basamak, iki yanında lamba (yarısında)
			var kapi := _sec(KAPILAR, _h(id, sl.fi, 2, 11))
			var zemin := -Sehir.KAT
			if kapi != "":
				_ekle(groups, kapi, key, cf * _duvar(kapi, cw * 0.5, zemin, 0.0))
			if _var("kapi_basamagi"):
				_ekle(groups, "kapi_basamagi", key, cf * _duvar("kapi_basamagi", cw * 0.5, zemin, 0.0))
			if _var("duvar_lambasi") and _h(id, sl.fi, 3, 7) < 0.7:
				for sx: float in [-1.0, 1.0]:
					_ekle(groups, "duvar_lambasi", key, cf * _duvar("duvar_lambasi", cw * 0.5 + sx * 1.05, zemin + 2.1, 0.0))
			continue
		var st: Dictionary = cephe.stiller[int(sl.style)]
		var parts: Array = st.satirlar.get(str(row), [])
		var cam := {}
		var balkon := {}
		var denizlik := {}
		for pt in parts:
			match String(pt.t):
				"cam":
					cam = pt
				"balkon":
					balkon = pt
				"denizlik":
					denizlik = pt
		var r := _h(id, sl.fi, sl.i, sl.fl)
		var esyali := r < YOGUNLUK
		if not balkon.is_empty() and esyali:
			var b := _sec(BALKON, _h(id, sl.fi * 7 + sl.i, sl.fl, 3))
			if b != "":
				var y := -float(balkon.y) * my
				var xf := cf * Transform3D(Basis(), Vector3((float(balkon.x) + float(balkon.w) * 0.5) * mx, y, 0.0))
				# Balkon zemininde, duvara yaslı (balkon 0,85 m derin)
				_ekle(groups, b, key, xf * Transform3D(Basis(), Vector3(0, 0, float(DERINLIK.get(b, 0.2)) + 0.05)))
		elif not cam.is_empty() and esyali and _var("cicek_kutusu"):
			var y := -float(denizlik.y) * my if not denizlik.is_empty() else -(float(cam.y) + float(cam.h)) * my
			var x := (float(cam.x) + float(cam.w) * 0.5) * mx
			_ekle(groups, "cicek_kutusu", key, cf * _duvar("cicek_kutusu", x, y, 0.0))
		# Perde / jaluzi: zemin kat hariç (canlı odalar ve vitrinler)
		if not cam.is_empty() and int(sl.fl) > 0 and _h(id, sl.fi, sl.i, sl.fl + 50) < PERDE_ORAN:
			if not perdeler.has(key):
				var stp := SurfaceTool.new()
				stp.begin(Mesh.PRIMITIVE_TRIANGLES)
				perdeler[key] = stp
			_perde(perdeler[key], cf, cam, mx, my, id, sl)
	for gk in groups:
		var parcalar: Array = String(gk).split("|")
		_multimesh(String(parcalar[0]), groups[gk])
	for key in perdeler:
		var mesh: ArrayMesh = (perdeler[key] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = VC_SHADER
		mi.material_override = m
		mi.visibility_range_end = 160.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)


func _var(model: String) -> bool:
	return ResourceLoader.exists(MODEL % model)


## Listeden modeli olanlar arasından k (0..1) ile seç
func _sec(liste: Array, k: float) -> String:
	var ok: Array = []
	for m in liste:
		if _var(m):
			ok.append(m)
	if ok.is_empty():
		return ""
	return ok[mini(int(k * ok.size()), ok.size() - 1)]


## Duvara yaslı model: bölmenin yerel (x, y) noktasında, arka yüzü duvarda
func _duvar(model: String, x: float, y: float, z: float) -> Transform3D:
	var taban := model.rstrip("_23")
	return Transform3D(Basis(), Vector3(x, y, z + float(DERINLIK.get(taban, 0.15)) + 0.005))


func _ekle(groups: Dictionary, model: String, key: Vector2i, xf: Transform3D) -> void:
	var gk := "%s|%d|%d" % [model, key.x, key.y]
	if not groups.has(gk):
		groups[gk] = []
	(groups[gk] as Array).append(xf)


func _multimesh(model: String, tfs: Array) -> void:
	var center := Vector3.ZERO
	for tf: Transform3D in tfs:
		center += tf.origin
	center /= tfs.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.position = center
	mmi.set_script(PROP_SCRIPT)
	mmi.set("model_path", MODEL % model)
	var rel: Array[Transform3D] = []
	for tf: Transform3D in tfs:
		rel.append(Transform3D(tf.basis, tf.origin - center))
	mmi.set("transforms", rel)
	mmi.visibility_range_end = 120.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
	# Çamaşırlar rüzgârla sallanır
	if model.begins_with("camasir_ipi"):
		var m := ShaderMaterial.new()
		m.shader = SALLA_SHADER
		mmi.material_override = m


## Pencereye perde / jaluzi: camın önünde (dokunun hemen üstünde) düz renkli parçalar
func _perde(st: SurfaceTool, cf: Transform3D, cam: Dictionary, mx: float, my: float, id: int, sl: Dictionary) -> void:
	var x0 := (float(cam.x) + 1.0) * mx
	var x1 := (float(cam.x) + float(cam.w) - 1.0) * mx
	var yt := -(float(cam.y) + 1.0) * my
	var yb := -(float(cam.y) + float(cam.h) - 1.0) * my
	var z := 0.012
	var hc := _h(id, int(sl.fi), int(sl.i) + 9, int(sl.fl))
	var renk := Color(PERDE_RENK[int(_h(id, int(sl.fl), 5, 1) * PERDE_RENK.size()) % PERDE_RENK.size()])
	renk.a = 0.88                  # gece hafifçe ışır (içeriden ışık)
	var koyu := Color(renk.r * 0.82, renk.g * 0.82, renk.b * 0.82, 0.88)
	var w := x1 - x0
	if hc < 0.45:
		# İki yanda toplanmış perde
		var pw := w * (0.22 + hc * 0.3)
		_dortgen(st, cf, x0, yb, x0 + pw, yt, z, renk)
		_dortgen(st, cf, x1 - pw, yb, x1, yt, z, renk)
		# Üstte kısa saçak
		_dortgen(st, cf, x0, yt - (yt - yb) * 0.12, x1, yt, z + 0.002, koyu)
	elif hc < 0.75:
		# Jaluzi: yarıya / tamamen inik, çizgili
		var inis := 0.45 + (hc - 0.45) * 1.8
		var alt := yt - (yt - yb) * minf(inis, 1.0)
		var n := 5
		for k in n:
			var a := yt - (yt - alt) * k / n
			var b := yt - (yt - alt) * (k + 0.8) / n
			_dortgen(st, cf, x0, b, x1, a, z, renk if k % 2 == 0 else koyu)
	else:
		# Yarım (kafe) perde: alt yarı
		var orta := yb + (yt - yb) * 0.48
		_dortgen(st, cf, x0, yb, x1, orta, z, renk)


func _dortgen(st: SurfaceTool, cf: Transform3D, x0: float, y0: float, x1: float, y1: float, z: float, col: Color) -> void:
	var n := (cf.basis * Vector3(0, 0, 1)).normalized()
	var ps := [cf * Vector3(x0, y0, z), cf * Vector3(x1, y0, z), cf * Vector3(x1, y1, z), cf * Vector3(x0, y1, z)]
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(ps[k])
