class_name Sehir
extends Node3D
## Şehri dolduran yerleşim: süs binaları, dükkânlar, Arnavut kaldırımlı ara sokaklar, merdivenler,
## yükseltiler ve korkuluklar. Veri assets/ada/sehir.json'da (oyun içi editör yazar: SehirEditor);
## açılışta ve her düzenlemede geometri bu veriden kurulur (hazır sahneye pişirme yok).
##
## Süs binaları "sahte 3D": hafif çıkıntılı kutular (silme, korniş, kaide) ve üstlerine basılmış
## piksel cepheler (assets/sehir/cepheler.png, shaders/bina.gdshader). Bütün binalar tek mesh.
## Korkuluk, merdiven korkuluğu ve yükselti kenarları grind yapılabilir (GrindRail).
##
## Öğeler ("t" türü; konumlar dünya x, z; yükseklik zeminden otomatik):
##   bina:     p, r (derece; ön yüz +Z), w, d, k (kat), s (stil), cati ("duz" / "besik")
##   dukkan:   p (kapı ortası), r, tur (DUKKAN_TURLERI), ad (tabela)
##   yol:      pts [[x, z]...], w            (Arnavut kaldırımlı ara sokak)
##   merdiven: a, b, w, korkuluk (bool)       (iki ucun zemini arasında basamaklar)
##   yukselti: p, r, w, d, h, s               (yükseltilmiş alan; üstü Arnavut kaldırımı)
##   korkuluk: pts, h

const DATA_PATH := "res://assets/ada/sehir.json"
const BINA_SHADER := preload("res://shaders/bina.gdshader")
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")
const COBBLE_SHADER := preload("res://shaders/cobble.gdshader")
const ATLAS := preload("res://assets/sehir/cepheler.png")
## Camdan görünen odalar (tools/sehir/oda_atlas.py) ve cephe parçalarının yerleri (cephe_atlas.py)
const ODALAR := preload("res://assets/sehir/odalar.png")
const CEPHE_JSON := "res://assets/sehir/cephe.json"
## Pervaz, denizlik, tente, balkon: bu mesafeden uzakta çizilmez (telefon)
const VIS_DETAY := 75.0
const KAT := 3.0
const BOLME := 3.0
## Şehir gövdelerinin çarpışma katmanı (zemin ışınları katman 1'e bakar: adanın kendisi)
const LAYER := 2
const VC_SHADER := preload("res://shaders/toon_vc.gdshader")
## Sıradan bina stilleri (cephe atlası sütunları 0-15; tools/sehir/cephe_atlas.py)
const STIL_ADLARI := ["Pembe", "Nane", "Krem", "Tuğla", "Lavanta", "Hardal", "Mavi", "Beton",
	"Terrakota", "Ahşap kaplama", "Sarı tuğla", "Somon", "Zeytin", "Gece mavisi", "Kesme taş", "Şeftali"]
## Bina türleri: "ev" sıradan; diğerleri özel (kendi cephe sütunu, ölçüleri ve süsleri)
const BINA_TURLERI := {
	"ev": {"ad": "Ev / apartman"},
	"muze": {"ad": "Müze", "stil": 16, "w": 16.0, "d": 12.0, "k": 2, "cati": "duz", "tabela": "MÜZE"},
	"sinema": {"ad": "Sinema", "stil": 17, "w": 12.0, "d": 14.0, "k": 2, "cati": "duz", "tabela": "SİNEMA"},
	"kafe": {"ad": "Kafe", "stil": 18, "w": 8.0, "d": 7.0, "k": 2, "cati": "besik", "tabela": "KAFE"},
	"otel": {"ad": "Otel", "stil": 19, "w": 12.0, "d": 10.0, "k": 5, "cati": "duz", "tabela": "OTEL"},
	"kutuphane": {"ad": "Kütüphane", "stil": 20, "w": 14.0, "d": 10.0, "k": 2, "cati": "besik", "tabela": "KÜTÜPHANE"},
	"firin": {"ad": "Fırın", "stil": 21, "w": 7.0, "d": 7.0, "k": 2, "cati": "besik", "tabela": "FIRIN"},
}
## Dükkân türleri: girilebilenler Dukkan sahnesiyle kurulur; diğerleri şimdilik dıştan
## (vitrinli bina ve tabela). Yeni bir girilebilir tür eklenince burada işaretlenir.
const DUKKAN_TURLERI := {
	"bakkal": {"ad": "Bakkal", "girilebilir": true, "w": 10.4, "d": 9.0, "stil": 0, "k": 1},
	"teknoloji": {"ad": "Teknoloji mağazası", "girilebilir": false, "w": 9.0, "d": 8.0, "stil": 6, "k": 2},
	"kiyafet": {"ad": "Kıyafet mağazası", "girilebilir": false, "w": 9.0, "d": 8.0, "stil": 4, "k": 2},
}
const VARSAYILAN := {
	"bina": {"tur": "ev", "w": 9.0, "d": 8.0, "k": 3, "s": 0, "cati": "duz", "zemin": "dukkan", "r": 0.0},
	"dukkan": {"tur": "bakkal", "ad": "YENİ BAKKAL", "r": 0.0},
	"yol": {"w": 2.6},
	"merdiven": {"w": 2.4, "korkuluk": true},
	"yukselti": {"w": 6.0, "d": 6.0, "h": 1.2, "s": 7, "r": 0.0},
	"park": {"w": 30.0, "d": 24.0, "r": 0.0},
	"korkuluk": {"h": 0.9},
	"yesil": {},
}

var player: SkateController
var follow_cam: Camera3D
var look: Node
var ui_parent: Node
## Adanın kendisi (arazi düzleştirme: yükseklik haritası ve görünen arazi parçaları)
var level: Node
## Şehir verisi yoksa: adanın ilk dükkânı (ada_builder "dukkan" meta'sı) başlangıç verisine girer
var initial_shop = null

var data := {"items": []}
var _built: Node3D
var _shops := {}                # öğe kimliği -> {"node", "key"}
var _mats := {}
var _plats: Array = []                # yükseltiler (zemin sorgusu her öğeyi taramasın)
## Şehir geometrisi 64 m'lik parçalara bölünür: görünmeyen ve uzak parçalar çizilmez (telefon)
const CHUNK := 64.0
const VIS_BINA := 420.0
const VIS_SUS := 160.0
var _sd: SurfaceTool                 # kurulum sırasında renkli süslerin yüzeyi
var _sdet: SurfaceTool               # kurulum sırasında cephe ayrıntılarının yüzeyi (pervaz, tente...)
static var _cephe: Dictionary = {}
## Gerçek 3D oda kurulabilecek yerler (binaların zemin kat ön cephesi): CanliOdalar okur
var room_slots: Array = []
## Çocuk parkları (CocukParki.build): çocukların oynayacağı yerler, salıncaklar, banklar (NpcCrowd okur)
var parks: Array = []
var _rooms: CanliOdalar
## Gece (0..1): odaların bir kısmının ışığı yanar. Gün döngüsü (henüz yok) bunu değiştirecek.
var gece := 0.0:
	set(v):
		gece = clampf(v, 0.0, 1.0)
		set_night(gece)
## Cephe çeşitlemesi için binanın tohumu (UV2.x): bütün köşelere yazılır
static var _seed := 0.0


func _ready() -> void:
	instance = self
	load_data()
	# Adanın çarpışma gövdeleri fizik dünyasına girsin (zemin ışınları onlara çarpar)
	for i in 3:
		await get_tree().physics_frame
	rebuild()


# ---------- Veri ----------

func load_data() -> void:
	if FileAccess.file_exists(DATA_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if d is Dictionary and d.has("items"):
			data = d
	elif initial_shop is Transform3D:
		var xf: Transform3D = initial_shop
		data.items.append({"t": "dukkan", "tur": "bakkal", "ad": "ZÜRAFA BAKKAL",
			"p": [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.z, 0.01)], "r": snappedf(rad_to_deg(xf.basis.get_euler().y), 0.1)})
	for it in data.items:
		if not it.has("id"):
			it["id"] = _new_id()


func save() -> bool:
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Şehir kaydedilemedi: " + DATA_PATH)
		return false
	# "_" ile başlayan alanlar çalışma anı bilgisi (ör. yükseltinin üst yüksekliği): kaydedilmez
	var items := []
	for it in data.items:
		var c := {}
		for k in it:
			if not String(k).begins_with("_"):
				c[k] = it[k]
		items.append(c)
	f.store_string(JSON.stringify({"items": items}, "\t"))
	f.close()
	return true


func _new_id() -> int:
	var m := 0
	for it in data.items:
		m = maxi(m, int(it.get("id", 0)))
	return m + 1


func new_item(t: String) -> Dictionary:
	var it: Dictionary = VARSAYILAN.get(t, {}).duplicate(true)
	it["t"] = t
	it["id"] = _new_id()
	return it


func add(it: Dictionary) -> void:
	if not it.has("id"):
		it["id"] = _new_id()
	data.items.append(it)
	rebuild()


func remove(it: Dictionary) -> void:
	data.items.erase(it)
	rebuild()


# ---------- Zemin ----------

## Zemin yüksekliği: adanın kendisi (ışın, katman 1) ve üstündeki yükseltiler
func ground(x: float, z: float, with_platforms := true) -> float:
	var sf := _surface_y(x, z)
	var h: float = float(sf.y) if not sf.is_empty() else 0.0
	if with_platforms:
		for it in _plats:
			if _in_rect(it, x, z, 0.0):
				h = maxf(h, float(it.get("_top", -INF)))
	return h


## Bu nokta boş arazi mi? Adanın hazır iskeleti (asfalt, kaldırım, kavşak, meydan, iskele,
## direk, tabela, sokak eşyası, dükkân) her zaman baskın: üstüne şehir öğesi çizilmez / konmaz.
func is_free(x: float, z: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -50.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or String((hit.collider as Node).name) == "AraziCarpisma"


func _terrain_init() -> bool:
	if _hm != null:
		return true
	if level == null:
		return false
	var body := level.get_node_or_null("AraziCarpisma")
	if body == null or body.get_child_count() == 0:
		return false
	var cs := body.get_child(0) as CollisionShape3D
	_hm = cs.shape as HeightMapShape3D
	if _hm == null:
		return false
	_hm_orig = _hm.map_data.duplicate()
	_hm_n = _hm.map_width
	_hm_step = cs.scale.x
	_hm_ext = (_hm_n - 1) * 0.5 * _hm_step
	_mask_n = int(ceil(_hm_ext * 2.0 / MASK_RES)) + 1
	_mask = Image.create(_mask_n, _mask_n, false, Image.FORMAT_R8)
	_mask_base = Image.create(_mask_n, _mask_n, false, Image.FORMAT_R8)
	_mask_tex = ImageTexture.create_from_image(_mask)
	var origin := -_hm_ext - MASK_RES * 0.5
	var rect := Vector4(origin, origin, _mask_n * MASK_RES, _mask_n * MASK_RES)
	for c in level.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Arazi"):
			var mi := c as MeshInstance3D
			var mat := mi.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("pave_mask", _mask_tex)
				mat.set_shader_parameter("pave_rect", rect)
			if String(c.name).begins_with("Arazi_"):
				var p := mi.position
				_chunks.append({"mi": mi, "arrays": mi.mesh.surface_get_arrays(0), "rect": Rect2(p.x - 66.0, p.z - 66.0, 132.0, 132.0)})
	_apply_blocks()
	return true


## Şehir blokları: hedef yükseklikler özgün araziye (çarpışma ve görünen) bir kez işlenir; boyası
## temel maskeye yazılır. Sonraki düzenlemeler bunun üstünden hesaplanır.
func _apply_blocks() -> void:
	if not FileAccess.file_exists(BLOCKS_PATH):
		return
	var bh := FileAccess.get_file_as_bytes(BLOCKS_PATH).to_float32_array()
	if bh.size() != _hm_n * _hm_n:
		return
	var tgt := {}                       # yükseklik haritası indisi -> hedef
	for j in _hm_n:
		var r := _hm_n - 1 - j            # plan y yukarı = Godot -z
		for i in _hm_n:
			var h := bh[j * _hm_n + i]
			if h > -9000.0:
				var idx := r * _hm_n + i
				tgt[idx] = h
				_hm_orig[idx] = h
	_hm.map_data = _hm_orig
	_block_cells = tgt
	for ch in _chunks:
		var arrays: Array = ch.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var org: Vector3 = (ch.mi as MeshInstance3D).position
		var any := false
		for k in verts.size():
			var v := verts[k]
			var idx := roundi((v.z + org.z + _hm_ext) / _hm_step) * _hm_n + roundi((v.x + org.x + _hm_ext) / _hm_step)
			if tgt.has(idx):
				v.y = float(tgt[idx]) - org.y
				verts[k] = v
				if norms.size() == verts.size():
					norms[k] = Vector3.UP
				any = true
		if any:
			arrays[Mesh.ARRAY_VERTEX] = verts
			if norms.size() == verts.size():
				arrays[Mesh.ARRAY_NORMAL] = norms
			ch.arrays = arrays
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			(ch.mi as MeshInstance3D).mesh = am
	# Boya: maske pikseli en yakın ızgara hücresine bakar
	for jj in _mask_n:
		var z := -_hm_ext + jj * MASK_RES
		var r := clampi(roundi((z + _hm_ext) / _hm_step), 0, _hm_n - 1)
		for ii in _mask_n:
			var x := -_hm_ext + ii * MASK_RES
			var i := clampi(roundi((x + _hm_ext) / _hm_step), 0, _hm_n - 1)
			if tgt.has(r * _hm_n + i):
				_mask_base.set_pixel(ii, jj, Color(1, 0, 0))
	_mask.copy_from(_mask_base)
	_mask_tex.update(_mask)


## Özgün arazinin yüksekliği (düzleştirmeden önce; çift doğrusal)
func _orig_h(x: float, z: float) -> float:
	var fx := clampf((x + _hm_ext) / _hm_step, 0.0, _hm_n - 1.001)
	var fz := clampf((z + _hm_ext) / _hm_step, 0.0, _hm_n - 1.001)
	var i := int(fx)
	var r := int(fz)
	var u := fx - i
	var v := fz - r
	var a := lerpf(_hm_orig[r * _hm_n + i], _hm_orig[r * _hm_n + i + 1], u)
	var b := lerpf(_hm_orig[(r + 1) * _hm_n + i], _hm_orig[(r + 1) * _hm_n + i + 1], u)
	return lerpf(a, b, v)


## Binanın oturacağı yükseklik: kapısı yakınında kaldırım varsa onun üstü (yol hizası), yoksa arazi
func _base_y(c: Vector2) -> float:
	var e := nearest_edge(c, 9.0)
	if not e.is_empty():
		var q := Geometry2D.get_closest_point_to_segment(c, e.a, e.b)
		var dir := (q - c).normalized()
		var sf := _surface_y(q.x + dir.x * 0.4, q.y + dir.y * 0.4)
		if not sf.is_empty() and not String(sf.name).begins_with("Arazi"):
			return float(sf.y)
	return _orig_h(c.x, c.y)


## ---------- Zemin: boyama (Arnavut kaldırımı) ve düzleştirme ----------
## Döşeme ayrı bir katman değil: arazinin kendisi boyanır (1 m çözünürlüklü maske, yuvarlak köşeli
## bölgeler; arazi gölgelendiricisi taş deseniyle karıştırır) ve yüksekliği ayarlanır:
##   - bina / dükkân altı: zeminin biraz altına iner (zemin döşemesinin içinden çimen görünmesin)
##   - önlük, komşular arası köprü, ara sokak: kaldırımla aynı hizada düz (basamaksız birleşir)
## Hazır iskeletin (yol, kaldırım) altındaki araziye dokunulmaz: asfalta taşma olmaz.

func _ground_regions() -> Array:
	var regions := []
	for it in data.items:
		var t := String(it.t)
		if t != "bina" and t != "dukkan":
			continue
		var b := _yaw(it)
		var ax := Vector2(b.x.x, b.x.z)
		var az := Vector2(b.z.x, b.z.z)
		var c := v2(it.p)
		var hw: float
		var hd: float
		var door: Vector2
		if t == "bina":
			hw = float(it.w) * 0.5
			hd = float(it.d) * 0.5
			door = c + az * hd
		else:
			var tp: Dictionary = DUKKAN_TURLERI.get(it.get("tur", "bakkal"), DUKKAN_TURLERI.bakkal)
			var dd := float(tp.d)
			door = c
			c = c + az * (0.9 - dd) * 0.5            # kapı önü basamağından arka duvara
			hw = float(tp.w) * 0.5
			hd = (dd + 0.9) * 0.5
		var y := _base_y(door)
		it["_y"] = y
		regions.append({"k": "foot", "c": c, "ax": ax, "az": az, "hw": hw + 0.3, "hd": hd + 0.3, "y0": y - 0.25, "y1": y - 0.25, "z": false, "rad": 0.0})
	# Çocuk parkları: düz zemin (ortalama arazi yüksekliği)
	for it in data.items:
		if String(it.t) != "park":
			continue
		var b := _yaw(it)
		var c := v2(it.p)
		var hw := CocukParki.W * 0.5
		var hd := CocukParki.D * 0.5
		var acc := 0.0
		for sx: float in [-0.8, 0.0, 0.8]:
			for sz: float in [-0.8, 0.0, 0.8]:
				var q: Vector3 = b * Vector3(sx * hw, 0, sz * hd)
				acc += _orig_h(c.x + q.x, c.y + q.z)
		var y := acc / 9.0
		it["_y"] = y
		regions.append({"k": "park", "c": c, "ax": Vector2(b.x.x, b.x.z), "az": Vector2(b.z.x, b.z.z), "hw": hw + 0.5, "hd": hd + 0.5,
			"y0": y, "y1": y, "z": false, "rad": 1.0})
	# Ara sokaklar: yuvarlak uçlu şeritler; yükseklik arazi, kaldırıma yaklaşınca kaldırım hizası
	for it in data.items:
		if String(it.t) != "yol":
			continue
		var pts: Array = it.pts
		if pts.size() < 2:
			continue
		var r := float(it.get("w", 2.6)) * 0.5
		var smp: Array[Vector2] = []
		for i in pts.size() - 1:
			var a := v2(pts[i])
			var b2 := v2(pts[i + 1])
			var n := maxi(int(ceil(a.distance_to(b2))), 1)
			for k in n:
				smp.append(a.lerp(b2, float(k) / n))
		smp.append(v2(pts[pts.size() - 1]))
		var hs := PackedFloat32Array()
		for p in smp:
			hs.append(_alley_h(p))
		var sm := hs.duplicate()
		for i in smp.size():
			var acc := 0.0
			var cnt := 0.0
			for k in range(-2, 3):
				var q := clampi(i + k, 0, smp.size() - 1)
				acc += hs[q]
				cnt += 1.0
			sm[i] = acc / cnt
		for i in smp.size() - 1:
			regions.append({"k": "seg", "a": smp[i], "b": smp[i + 1], "y0": sm[i], "y1": sm[i + 1], "rad": r})
	# Yeşil alanlar (kullanıcı çizer): çokgen; yalnız boyayı kaldırır
	for it in data.items:
		if String(it.t) == "yesil" and (it.pts as Array).size() >= 3:
			var poly := PackedVector2Array()
			for q in it.pts:
				poly.append(v2(q))
			regions.append({"k": "yesil", "poly": poly, "rad": 0.0})
	return regions


## Ara sokağın o noktadaki yüksekliği: kaldırım / yol üstündeyse onun yüzeyi; kaldırıma 2,5 m'den
## yakınsa kaldırım hizası (basamaksız birleşsin); yoksa özgün arazi
func _alley_h(p: Vector2) -> float:
	var pr := _surface_y(p.x, p.y)
	if not pr.is_empty() and not String(pr.name).begins_with("Arazi"):
		return float(pr.y)
	var e := nearest_edge(p, 2.5)
	if not e.is_empty():
		var q := Geometry2D.get_closest_point_to_segment(p, e.a, e.b)
		var dir := (q - p).normalized()
		var sp := _surface_y(q.x + dir.x * 0.4, q.y + dir.y * 0.4)
		if not sp.is_empty() and not String(sp.name).begins_with("Arazi"):
			return float(sp.y)
	return _orig_h(p.x, p.y)


## Bölgeye işaretli uzaklık (içeride eksi) ve o noktadaki hedef yükseklik
static func _region_sd(rg: Dictionary, p: Vector2) -> float:
	if rg.k == "yesil":
		var poly: PackedVector2Array = rg.poly
		var d := INF
		for k in poly.size():
			var cp := Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])
			d = minf(d, cp.distance_to(p))
		return -d if Geometry2D.is_point_in_polygon(p, poly) else d
	if rg.k == "seg":
		var cp := Geometry2D.get_closest_point_to_segment(p, rg.a, rg.b)
		return cp.distance_to(p) - float(rg.rad)
	var rel: Vector2 = p - (rg.c as Vector2)
	var rad: float = rg.rad
	var q := Vector2(absf(rel.dot(rg.ax)) - (float(rg.hw) - rad), absf(rel.dot(rg.az)) - (float(rg.hd) - rad))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rad


static func _region_h(rg: Dictionary, p: Vector2) -> float:
	if rg.k == "seg":
		var ab: Vector2 = (rg.b as Vector2) - (rg.a as Vector2)
		var t := clampf((p - (rg.a as Vector2)).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		return lerpf(rg.y0, rg.y1, t)
	var rel: Vector2 = p - (rg.c as Vector2)
	var t: float
	if rg.z:
		t = clampf((rel.dot(rg.az) + float(rg.hd)) / (float(rg.hd) * 2.0), 0.0, 1.0)
	else:
		t = clampf((rel.dot(rg.ax) + float(rg.hw)) / (float(rg.hw) * 2.0), 0.0, 1.0)
	return lerpf(rg.y0, rg.y1, t)


static func _region_box(rg: Dictionary, pad: float) -> Rect2:
	if rg.k == "yesil":
		var poly: PackedVector2Array = rg.poly
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		return bb.grow(pad)
	if rg.k == "seg":
		var a: Vector2 = rg.a
		var b: Vector2 = rg.b
		var r := float(rg.rad) + pad
		return Rect2(minf(a.x, b.x) - r, minf(a.y, b.y) - r, absf(a.x - b.x) + r * 2.0, absf(a.y - b.y) + r * 2.0)
	var R := Vector2(float(rg.hw), float(rg.hd)).length() + pad
	var c: Vector2 = rg.c
	return Rect2(c.x - R, c.y - R, R * 2.0, R * 2.0)


func _ground_update() -> void:
	if not _terrain_init():
		return
	var regions := _ground_regions()
	var key := JSON.stringify(regions)
	if key == _flat_key:
		return
	_flat_key = key
	# 1) Hücre hedefleri: [ağırlık, hedef, bina altı mı]
	var cells := {}
	for rg in regions:
		var box := _region_box(rg, FLAT_FALL)
		var i0 := maxi(int(floor((box.position.x + _hm_ext) / _hm_step)), 0)
		var i1 := mini(int(ceil((box.end.x + _hm_ext) / _hm_step)), _hm_n - 1)
		var r0 := maxi(int(floor((box.position.y + _hm_ext) / _hm_step)), 0)
		var r1 := mini(int(ceil((box.end.y + _hm_ext) / _hm_step)), _hm_n - 1)
		var deep: bool = rg.k == "foot"
		if rg.k == "yesil":
			continue
		for r in range(r0, r1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-_hm_ext + i * _hm_step, -_hm_ext + r * _hm_step)
				var sd := _region_sd(rg, p)
				var idx := r * _hm_n + i
				if deep:
					if sd <= 0.0 and not _block_cells.has(idx):
						cells[idx] = [1.0, float(rg.y0), true]
					continue
				var w := 1.0 if sd <= 0.0 else 1.0 - smoothstep(0.0, FLAT_FALL, sd)
				if w <= 0.0 or _block_cells.has(idx):
					continue            # blok yüzeyi zaten düz ve kaldırım hizasında
				if cells.has(idx) and (cells[idx][2] or float(cells[idx][0]) >= w):
					continue
				cells[idx] = [w, _region_h(rg, p) - 0.03, false]
	# Yol / kaldırım altındaki araziye dokunma
	for idx in cells.keys():
		if _block_cells.has(idx):
			continue
		var p := Vector2(-_hm_ext + (idx % _hm_n) * _hm_step, -_hm_ext + floori(float(idx) / _hm_n) * _hm_step)
		if not is_free(p.x, p.y):
			cells.erase(idx)
	# Çarpışma
	var hm := _hm_orig.duplicate()
	for idx in cells:
		var wt: Array = cells[idx]
		hm[idx] = lerpf(_hm_orig[idx], float(wt[1]), wt[0])
	_hm.map_data = hm
	# Görünen arazi: değişen ve önceki seferde değişmiş parçalar (görünen = çarpışma)
	var touched := {}
	for ch in _chunks:
		var rect: Rect2 = ch.rect
		for rg in regions:
			if rect.intersects(_region_box(rg, FLAT_FALL)):
				touched[ch.mi] = ch
				break
	for mi in _flat_chunks:
		if is_instance_valid(mi):
			touched[mi] = _flat_chunks[mi]
	var now := {}
	for mi in touched:
		var ch: Dictionary = touched[mi]
		var arrays: Array = (ch.arrays as Array).duplicate()
		var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var norms: PackedVector3Array = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var org: Vector3 = (mi as MeshInstance3D).position
		var any := false
		for k in verts.size():
			var v := verts[k]
			var i := roundi((v.x + org.x + _hm_ext) / _hm_step)
			var r := roundi((v.z + org.z + _hm_ext) / _hm_step)
			var idx := r * _hm_n + i
			if cells.has(idx):
				var wt: Array = cells[idx]
				v.y = lerpf(v.y, float(wt[1]) - org.y, wt[0])
				verts[k] = v
				if norms.size() == verts.size():
					norms[k] = norms[k].lerp(Vector3.UP, wt[0]).normalized()
				any = true
		arrays[Mesh.ARRAY_VERTEX] = verts
		if norms.size() == verts.size():
			arrays[Mesh.ARRAY_NORMAL] = norms
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		(mi as MeshInstance3D).mesh = am
		if any:
			now[mi] = ch
	_flat_chunks = now
	# 2) Boyama maskesi (yuvarlak köşeli bölgeler; arazi gölgelendiricisi okur)
	_mask.copy_from(_mask_base)
	var ordered := []
	for rg in regions:
		if rg.k == "yesil":
			ordered.append(rg)
	for rg in regions:
		if rg.k == "seg":
			ordered.append(rg)
	for rg in ordered:
		var box := _region_box(rg, 1.0)
		var i0 := maxi(int(floor((box.position.x + _hm_ext) / MASK_RES)), 0)
		var i1 := mini(int(ceil((box.end.x + _hm_ext) / MASK_RES)), _mask_n - 1)
		var j0 := maxi(int(floor((box.position.y + _hm_ext) / MASK_RES)), 0)
		var j1 := mini(int(ceil((box.end.y + _hm_ext) / MASK_RES)), _mask_n - 1)
		if rg.k == "yesil":
			_fill_poly(rg.poly as PackedVector2Array, j0, j1)
			continue
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-_hm_ext + i * MASK_RES, -_hm_ext + j * MASK_RES)
				var cov := clampf(0.5 - _region_sd(rg, p) / MASK_RES, 0.0, 1.0)
				if cov > 0.0 and cov > _mask.get_pixel(i, j).r:
					_mask.set_pixel(i, j, Color(cov, 0, 0))
	_mask_tex.update(_mask)


## Çim çokgeni: satır satır kesişimler arasını boyasız yap (büyük parklar da hızlı)
func _fill_poly(poly: PackedVector2Array, j0: int, j1: int) -> void:
	var n := poly.size()
	for j in range(j0, j1 + 1):
		var z := -_hm_ext + j * MASK_RES
		var xs := PackedFloat32Array()
		for k in n:
			var a := poly[k]
			var b := poly[(k + 1) % n]
			if (a.y > z) != (b.y > z):
				xs.append(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var i0 := maxi(int(ceil((xs[k] + _hm_ext) / MASK_RES)), 0)
			var i1 := mini(int(floor((xs[k + 1] + _hm_ext) / MASK_RES)), _mask_n - 1)
			if i1 >= i0:
				_mask.fill_rect(Rect2i(i0, j, i1 - i0 + 1, 1), Color(0, 0, 0))
	# Kenar şeridi: kenarlara 2 m yakın pikseller çokgene işaretli uzaklıkla (düz, keskin çizgi)
	var near := {}
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(2, 2)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(2, 2)
		for jj in range(maxi(int(floor((lo.y + _hm_ext) / MASK_RES)), 0), mini(int(ceil((hi.y + _hm_ext) / MASK_RES)), _mask_n - 1) + 1):
			for ii in range(maxi(int(floor((lo.x + _hm_ext) / MASK_RES)), 0), mini(int(ceil((hi.x + _hm_ext) / MASK_RES)), _mask_n - 1) + 1):
				var p := Vector2(-_hm_ext + ii * MASK_RES, -_hm_ext + jj * MASK_RES)
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= 2.0:
					near[Vector2i(ii, jj)] = p
	for key in near:
		var p: Vector2 = near[key]
		var d := INF
		for k in n:
			d = minf(d, Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % n]).distance_to(p))
		var inside := Geometry2D.is_point_in_polygon(p, poly)
		var keep := clampf(0.5 + (-d if inside else d) / MASK_RES, 0.0, 1.0)
		var now := _mask.get_pixel(key.x, key.y).r
		if inside or keep < now:
			_mask.set_pixel(key.x, key.y, Color(keep, 0, 0))


## Bu nokta Arnavut kaldırımıyla boyalı mı? (kaykayın yüzey hissi için)
func paved_at(x: float, z: float) -> bool:
	if _mask == null:
		return false
	var i := roundi((x + _hm_ext) / MASK_RES)
	var j := roundi((z + _hm_ext) / MASK_RES)
	if i < 0 or j < 0 or i >= _mask_n or j >= _mask_n:
		return false
	return _mask.get_pixel(i, j).r > 0.5


## Yürünen yüzeyler (adanın çarpışma gövdeleri): direk, tabela, lamba, bariyer gibi şeyler değil
const SURFACES := ["Kaldirim", "Yol", "Kavsak", "Meydan", "Arazi", "Iskele"]


## Noktadaki yürünen yüzey: {y, name} ya da boş. Önündeki direk / tabela / sokak eşyası atlanır
## (yoksa lambanın tepesi zemin sanılıyor, bina ve döşeme 4 m havaya kalkıyordu).
func _surface_y(x: float, z: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = []
	for k in 5:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -50.0, z), 1, excl)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var nm := String((hit.collider as Node).name)
		for pre in SURFACES:
			if nm.begins_with(pre):
				return {"y": hit.position.y, "name": nm}
		excl.append(hit.rid)
	return {}


## Noktadaki yüzey: {free: boş arazi mi, y: yüksekliği} (adanın kendisi, katman 1)
func _probe(x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -50.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"free": true, "y": 0.0}
	return {"free": String((hit.collider as Node).name) == "AraziCarpisma", "y": hit.position.y}


## Dikdörtgen ayak izi (merkez c, yön, en, derinlik; dükkânda kapıdan arkaya) boş arazide mi?
func footprint_free(it: Dictionary) -> bool:
	var ol := outline(it)
	if ol.size() < 5:
		return true
	# Köşelerden ızgara: ~1,5 m'de bir nokta (kenardan 0,25 m içeride)
	var o := ol[0]
	var ex := ol[1] - ol[0]
	var ey := ol[3] - ol[0]
	var nx := maxi(int(ceil(ex.length() / 1.5)), 1)
	var ny := maxi(int(ceil(ey.length() / 1.5)), 1)
	var ix := ex.normalized() * 0.25
	var iy := ey.normalized() * 0.25
	for i in nx + 1:
		for j in ny + 1:
			var p := o + ex * (float(i) / nx) + ey * (float(j) / ny)
			p += ix * (1.0 if i == 0 else (-1.0 if i == nx else 0.0))
			p += iy * (1.0 if j == 0 else (-1.0 if j == ny else 0.0))
			if not is_free(p.x, p.y):
				return false
	return true


## Kaldırımların dış kenarları (arazi tarafı): editörün yol mıknatısı binaları buraya yaslar.
## assets/ada/ada.json "sidewalks": her nokta [iç x, iç y, dış x, dış y, h] (plan düzlemi; Godot z = -y)
var _edges: Array = []                 # [a: Vector2, b: Vector2] (dünya x, z)

# ---------- Arazi düzleştirme ----------
# Bina ve dükkânların altı yol hizasına (yakında kaldırım varsa onun yüksekliğine) düzleşir,
# çevresinde ~4 m'de yamaca yumuşakça bağlanır. Her kurulumda özgün yüksekliklerden yeniden
# hesaplanır (taşınan / silinen binanın eski yeri geri gelir). Çarpışma (HeightMapShape3D) ve
# görünen yakın arazi parçaları ("Arazi_i_j", 2 m ızgara) birlikte güncellenir.
const FLAT_FALL := 4.0
var _hm: HeightMapShape3D
var _hm_orig := PackedFloat32Array()
var _hm_n := 0
var _hm_step := 2.0
var _hm_ext := 0.0
var _chunks: Array = []                # {mi, arrays, rect}
var _flat_key := ""
var _flat_chunks := {}                 # en son değiştirilen parçalar (geri yüklemek için)
## Şehir blokları (tools/ada/ada_export.js "bloklar.bin"): yollarla çevrili düz alanlar varsayılan
## olarak Arnavut kaldırımı; yükseklikleri kenarda kaldırım hizasında. Yeşil alanları kullanıcı ekler.
const BLOCKS_PATH := "res://assets/ada/bloklar.bin"
const MASK_RES := 1.0                   # boyama maskesinin çözünürlüğü (m / piksel)
var _mask_base: Image                   # blokların boyası (açılışta bir kez)
var _block_cells := {}                  # blok hücreleri (yükseklik haritası indisi): ara sokak bozmasın
## Kaykayın yüzey hissi için (boyalı arazi = Arnavut kaldırımı)
static var instance: Sehir
var _mask: Image
var _mask_tex: ImageTexture
var _mask_n := 0
var _edge_grid := {}                   # 16 m hücre -> kenar indisleri


func _load_edges() -> void:
	if not _edges.is_empty() or not FileAccess.file_exists("res://assets/ada/ada.json"):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/ada.json"))
	if not (d is Dictionary):
		return
	for run in d.get("sidewalks", []):
		var pts: Array = run.pts
		for i in pts.size() - 1:
			var a := Vector2(float(pts[i][2]), -float(pts[i][3]))
			var b := Vector2(float(pts[i + 1][2]), -float(pts[i + 1][3]))
			if a.distance_to(b) < 0.05:
				continue
			var id := _edges.size()
			_edges.append([a, b])
			var lo := Vector2i(floori(minf(a.x, b.x) / 16.0), floori(minf(a.y, b.y) / 16.0))
			var hi := Vector2i(floori(maxf(a.x, b.x) / 16.0), floori(maxf(a.y, b.y) / 16.0))
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					var key := Vector2i(gx, gy)
					if not _edge_grid.has(key):
						_edge_grid[key] = []
					_edge_grid[key].append(id)


## p'ye en yakın kaldırım dış kenarı (radius içinde): {a, b, d} ya da boş
func nearest_edge(p: Vector2, radius: float) -> Dictionary:
	_load_edges()
	var best := {}
	var bd := radius
	var c := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	var r := int(ceil(radius / 16.0))
	var seen := {}
	for gx in range(c.x - r, c.x + r + 1):
		for gy in range(c.y - r, c.y + r + 1):
			for id in _edge_grid.get(Vector2i(gx, gy), []):
				if seen.has(id):
					continue
				seen[id] = true
				var e: Array = _edges[id]
				var q := Geometry2D.get_closest_point_to_segment(p, e[0], e[1])
				var dd := q.distance_to(p)
				if dd < bd:
					bd = dd
					best = {"a": e[0], "b": e[1], "d": dd}
	return best


## Dükkânın binası (kapı önü basamağı hariç): çakışma denetimi için
func shop_body_outline(it: Dictionary) -> Dictionary:
	var tp: Dictionary = DUKKAN_TURLERI.get(it.get("tur", "bakkal"), DUKKAN_TURLERI.bakkal)
	var back: Vector3 = _yaw(it) * Vector3(0, 0, -float(tp.d) * 0.5)
	return {"t": "bina", "p": [float(it.p[0]) + back.x, float(it.p[1]) + back.z], "r": it.get("r", 0.0), "w": tp.w, "d": float(tp.d) - 0.4}


## Öğe hazır iskeletle çakışıyor mu? (bina, yükselti, dükkân; çizgiler kendini kırpar)
func overlaps_base(it: Dictionary) -> bool:
	match String(it.t):
		"bina", "yukselti":
			return not footprint_free(it)
		"dukkan":
			return not footprint_free(shop_body_outline(it))
	return false


static func _yaw(it: Dictionary) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(float(it.get("r", 0.0))))


static func v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _in_rect(it: Dictionary, x: float, z: float, pad: float) -> bool:
	var c := v2(it.p)
	var b := _yaw(it)
	var rel := Vector3(x - c.x, 0, z - c.y)
	var lx := rel.dot(b.x)
	var lz := rel.dot(b.z)
	return absf(lx) <= float(it.w) * 0.5 + pad and absf(lz) <= float(it.d) * 0.5 + pad


## Öğenin tepeden görünen sınırı (editör çizer ve seçer): kapalı çokgen ya da çizgi
func outline(it: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	match String(it.t):
		"bina", "yukselti", "park":
			var c := v2(it.p)
			var b := _yaw(it)
			var hw := float(it.get("w", CocukParki.W)) * 0.5
			var hd := float(it.get("d", CocukParki.D)) * 0.5
			for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
				var p: Vector3 = b * Vector3(s.x * hw, 0, s.y * hd)
				out.append(c + Vector2(p.x, p.z))
		"dukkan":
			var c := v2(it.p)
			var b := _yaw(it)
			var tp: Dictionary = DUKKAN_TURLERI.get(it.get("tur", "bakkal"), DUKKAN_TURLERI.bakkal)
			var hw := float(tp.w) * 0.5
			var dd := float(tp.d)
			for s: Vector2 in [Vector2(-1, 0.9), Vector2(1, 0.9), Vector2(1, -dd), Vector2(-1, -dd), Vector2(-1, 0.9)]:
				var p: Vector3 = b * Vector3(s.x * hw, 0, s.y)
				out.append(c + Vector2(p.x, p.z))
		"yol", "korkuluk":
			for q in it.pts:
				out.append(v2(q))
		"yesil":
			for q in it.pts:
				out.append(v2(q))
			if (it.pts as Array).size() > 0:
				out.append(v2(it.pts[0]))
		"merdiven":
			out.append(v2(it.a))
			out.append(v2(it.b))
	return out


## Bu noktadaki öğe (üstteki / en yakın); yoksa -1
func item_at(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in data.items.size():
		var it: Dictionary = data.items[i]
		var d := INF
		match String(it.t):
			"bina", "yukselti", "park":
				if _in_rect(it, p.x, p.y, 0.4):
					d = 0.5 if it.t == "bina" else (1.5 if it.t == "park" else 1.0)
			"dukkan":
				var ol := outline(it)
				if Geometry2D.is_point_in_polygon(p, ol.slice(0, 4)):
					d = 0.5
			"yesil":
				var ol := outline(it)
				if ol.size() >= 4 and Geometry2D.is_point_in_polygon(p, ol.slice(0, ol.size() - 1)):
					d = 2.0
			"yol", "korkuluk", "merdiven":
				var ol := outline(it)
				var w := float(it.get("w", 0.6)) * 0.5 + 0.4
				for k in ol.size() - 1:
					var cp := Geometry2D.get_closest_point_to_segment(p, ol[k], ol[k + 1])
					if cp.distance_to(p) < w:
						d = minf(d, cp.distance_to(p) * 0.1)
		if d < bd:
			bd = d
			best = i
	return best


# ---------- Kurulum ----------

func _mat_color(c: Color) -> ShaderMaterial:
	var k := c.to_html()
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = CHAR_SHADER
		m.set_shader_parameter("albedo", c)
		_mats[k] = m
	return _mats[k]


func _bina_mat() -> ShaderMaterial:
	if not _mats.has("bina"):
		var m := ShaderMaterial.new()
		m.shader = BINA_SHADER
		m.set_shader_parameter("atlas", ATLAS)
		m.set_shader_parameter("cells", Vector2(ATLAS.get_width() / 32.0, ATLAS.get_height() / 32.0))
		m.set_shader_parameter("rooms", ODALAR)
		_mats["bina"] = m
	return _mats["bina"]


func bina_material() -> ShaderMaterial:
	return _bina_mat()


## Gece: odaların bir kısmının ışığı yanar (0 gündüz .. 1 gece). Gün döngüsü bunu çağırır.
func set_night(v: float) -> void:
	_bina_mat().set_shader_parameter("gece", clampf(v, 0.0, 1.0))


func _cobble_mat() -> ShaderMaterial:
	if not _mats.has("cobble"):
		var m := ShaderMaterial.new()
		m.shader = COBBLE_SHADER
		_mats["cobble"] = m
	return _mats["cobble"]


## Bütün şehri yeniden kur (dükkânlar yalnız değiştiyse yeniden oluşur)
func rebuild() -> void:
	for it in data.items:
		if not it.has("id"):
			it["id"] = _new_id()
	if _built:
		remove_child(_built)
		_built.free()
	_built = Node3D.new()
	_built.name = "Yapilar"
	add_child(_built)
	room_slots.clear()
	if Banklar.instance:
		for pk in parks:
			Banklar.instance.remove_tagged("park_%d" % int(pk.id))
	parks.clear()
	if _rooms == null:
		_rooms = CanliOdalar.new()
		_rooms.name = "CanliOdalar"
		_rooms.city = self
		add_child(_rooms)
	else:
		_rooms._clear()
	_plats = []
	_ground_update()
	# Yükseltiler önce: üstleri merdiven ve korkulukların zemini
	for it in data.items:
		if it.t == "yukselti":
			it["_top"] = ground(float(it.p[0]), float(it.p[1]), false) + float(it.get("h", 1.0))
			_plats.append(it)
	var seen := {}
	var chunks := {}                   # parça -> [binalar, Arnavut, beton, metal, süsler]
	for it in data.items:
		var anchor = it.get("p", it.get("a", (it.get("pts", [[0, 0]]) as Array)[0] if it.has("pts") else [0, 0]))
		var key := Vector2i(floori(float(anchor[0]) / CHUNK), floori(float(anchor[1]) / CHUNK))
		if not chunks.has(key):
			var set := []
			for k in 6:
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				set.append(st)
			chunks[key] = set
		var sts: Array = chunks[key]
		var sb: SurfaceTool = sts[0]
		var sc: SurfaceTool = sts[1]
		var sk: SurfaceTool = sts[2]
		var sm: SurfaceTool = sts[3]
		_sd = sts[4]
		_sdet = sts[5]
		match String(it.t):
			"bina":
				_build_bina(it, sb)
			"yukselti":
				_build_platform(it, sb, sc, sk)
			"yol":
				pass                     # ara sokak: arazi boyanır ve düzleşir (_ground_update)
			"merdiven":
				_build_stairs(it, sk, sm)
			"korkuluk":
				_build_railing(it, sm)
			"dukkan":
				_build_shop(it, sb)
				seen[int(it.id)] = true
			"park":
				var pc := v2(it.p)
				var pxf := Transform3D(_yaw(it), Vector3(pc.x, float(it.get("_y", ground(pc.x, pc.y, false))), pc.y))
				parks.append(CocukParki.build(self, it, pxf, sk, sm, _sd))
	# Silinen dükkânlar
	for id in _shops.keys():
		if not seen.has(id):
			var n: Node = _shops[id].node
			if is_instance_valid(n):
				n.queue_free()
			_shops.erase(id)
	if not _mats.has("vc"):
		var vm := ShaderMaterial.new()
		vm.shader = VC_SHADER
		_mats["vc"] = vm
	for key in chunks:
		var sts: Array = chunks[key]
		var tag := "_%d_%d" % [key.x, key.y]
		_commit(sts[0], _bina_mat(), "Binalar" + tag, VIS_BINA)
		_commit(sts[1], _cobble_mat(), "Arnavut" + tag, VIS_SUS)
		_commit(sts[2], _mat_color(Color(0.74, 0.72, 0.68)), "Beton" + tag, VIS_SUS)
		_commit(sts[3], _mat_color(Color(0.22, 0.25, 0.3)), "Korkuluklar" + tag, VIS_SUS)
		_commit(sts[4], _mats.vc, "Susler" + tag, VIS_SUS)
		_commit(sts[5], _mats.vc, "Cephe" + tag, VIS_DETAY, false)
	_sd = null
	_sdet = null
	if look and look.has_method("add_root"):
		look.add_root(_built)


func _commit(st: SurfaceTool, mat: Material, name: String, vis := 0.0, shadow := true) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis > 0.0:
		mi.visibility_range_end = vis
		mi.visibility_range_end_margin = 20.0
	mi.name = name
	mi.mesh = mesh
	_built.add_child(mi)


func _body(surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.set_meta("surface", surface)
	_built.add_child(body)
	return body


func _shape_box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = xf
	body.add_child(cs)


func _rail(a: Vector3, b: Vector3, surface: String) -> void:
	if a.distance_to(b) < 0.3:
		return
	var r := GrindRail.new()
	r.setup(a, b, surface)
	_built.add_child(r)


# ---------- Geometri yardımcıları ----------

## Dörtgen (saat yönü ön yüz; normal n'e göre sıra düzeltilir)
static func _quad(st: SurfaceTool, ps: Array, uvs: Array, n: Vector3, col: Color) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (ps[1] - ps[0]).cross(ps[2] - ps[0]).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(_seed, 0.0))
		st.add_vertex(ps[k])


static func _tri(st: SurfaceTool, ps: Array, uvs: Array, n: Vector3, col: Color) -> void:
	var order := [0, 1, 2]
	if (ps[1] - ps[0]).cross(ps[2] - ps[0]).dot(n) > 0.0:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(_seed, 0.0))
		st.add_vertex(ps[k])


## Kutu: xf yerel çerçeve, c merkez, s boyut (yerel); uv hücre içi sabit
static func _box(st: SurfaceTool, xf: Transform3D, c: Vector3, s: Vector3, col: Color, top := true) -> void:
	var h := s * 0.5
	var uv := [Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)]
	var faces := [
		[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)]],
		[Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
		[Vector3(0, 0, -1), [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]],
		[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
	]
	if not top:
		faces.pop_back()
	for f in faces:
		var n: Vector3 = (xf.basis * f[0]).normalized()
		var ps := []
		for q in f[1]:
			ps.append(xf * (c + h * q))
		_quad(st, ps, uv, n, col)


## Ayak izi çevresinde çerçeve (silme, korniş, kaide): dışa "out" kadar taşan, "t" kalın 4 kutu
static func _ring(st: SurfaceTool, xf: Transform3D, w: float, d: float, y0: float, y1: float, out: float, t: float, col: Color) -> void:
	var h := y1 - y0
	var ym := (y0 + y1) * 0.5
	var W := w + out * 2.0
	var Dd := d + out * 2.0
	_box(st, xf, Vector3(0, ym, Dd * 0.5 - t * 0.5), Vector3(W, h, t), col)
	_box(st, xf, Vector3(0, ym, -Dd * 0.5 + t * 0.5), Vector3(W, h, t), col)
	_box(st, xf, Vector3(W * 0.5 - t * 0.5, ym, 0), Vector3(t, h, Dd - t * 2.0), col)
	_box(st, xf, Vector3(-W * 0.5 + t * 0.5, ym, 0), Vector3(t, h, Dd - t * 2.0), col)


## Atlas hücresi rengi (silme, çatı, düz duvar): r stil, b satır, a 0
static func _fc(style: int, _door: int, row: int, _shop_ground := true) -> Color:
	return Color(style / 255.0, 0.0, row / 255.0, 0.0)


## Cephe hücresi rengi: a 1 = cephe (camda oda çizilir, zemin altına kaide uzar)
static func _cell_col(style: int, row: int) -> Color:
	return Color(style / 255.0, 0.0, row / 255.0, 1.0)


static func _cephe_data() -> Dictionary:
	if _cephe.is_empty():
		_cephe = JSON.parse_string(FileAccess.get_file_as_string(CEPHE_JSON))
	return _cephe


# ---------- Bina ----------

static func _hash(a: float) -> float:
	return fposmod(sin(a * 12.9898 + 78.233) * 43758.5453, 1.0)


## Süs rengi (renkli süsler yüzeyi); glow > 0: kendiliğinden parlar (ampul, neon)
static func _vc(hex: String, glow := 0.0) -> Color:
	var c := Color(hex)
	c.a = 1.0 - glow
	return c


func _build_bina(it: Dictionary, sb: SurfaceTool) -> void:
	var tur := String(it.get("tur", "ev"))
	var spec: Dictionary = BINA_TURLERI.get(tur, BINA_TURLERI.ev)
	var ozel := tur != "ev" and BINA_TURLERI.has(tur)
	var c := v2(it.p)
	var basis := _yaw(it)
	var w := float(it.w)
	var d := float(it.d)
	var k := maxi(int(it.get("k", 2)), 1)
	var style: int = int(spec.stil) if ozel else clampi(int(it.get("s", 0)), 0, STIL_ADLARI.size() - 1)
	var shop_ground := ozel or String(it.get("zemin", "dukkan")) == "dukkan"
	var seed := float(int(it.get("id", 0)) % 997) + 1.0
	_seed = seed
	# Zemin: ön yüzün ortası (kapı) ve köşelerin en alçağı (yamaçta duvar toprağa gömülsün)
	var front: Vector3 = basis * Vector3(0, 0, d * 0.5)
	var yg: float = float(it["_y"]) if it.has("_y") else ground(c.x + front.x, c.y + front.z)
	var ylow := yg
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = basis * Vector3(s.x * w * 0.5, 0, s.y * d * 0.5)
		ylow = minf(ylow, ground(c.x + p.x, c.y + p.z))
	var xf := Transform3D(basis, Vector3(c.x, yg, c.y))
	var ybot := ylow - yg - 0.6
	var top := k * KAT
	var nbw := maxi(roundi(w / BOLME), 1)
	var nbd := maxi(roundi(d / BOLME), 1)
	var door := nbw / 2 + 1
	var hw := w * 0.5
	var hd := d * 0.5
	var v0 := ybot / KAT
	var v1 := float(k)
	# Dört cephe: u soldan sağa (dışarıdan bakınca), v kat
	var faces := [
		[Vector3(0, 0, 1), Vector3(-hw, 0, hd), Vector3(hw, 0, hd), nbw, door],
		[Vector3(0, 0, -1), Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), nbw, 0],
		[Vector3(1, 0, 0), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), nbd, 0],
		[Vector3(-1, 0, 0), Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), nbd, 0],
	]
	# Gerçek oda yuvası: zemin kat ön cephe (yalnız sıradan binalar; özellerin önünde süs var)
	if not ozel:
		# Pencere bölmelerinin ortaları (kapı bölmesi hariç), cephenin ortasına göre
		var bays: Array = []
		var bcw := w / nbw
		for i in nbw:
			if i != door - 1:
				bays.append(-hw + (i + 0.5) * bcw)
		bays.sort_custom(func(a, b): return absf(a) < absf(b))
		room_slots.append({"id": int(it.get("id", 0)), "center": xf * Vector3(0, 0, hd), "normal": (basis * Vector3(0, 0, 1)).normalized(),
			"width": w, "depth": d, "shop": shop_ground, "seed": seed, "bays": bays})
	var odd_b := _hash(seed * 3.7) < 0.35
	var mid_b := _hash(seed * 5.3) < 0.45
	for fi in faces.size():
		var f: Array = faces[fi]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var nb: int = f[3]
		var fdoor: int = f[4]
		var n: Vector3 = f[0]
		var dir := (b - a).normalized()
		var cw := a.distance_to(b) / nb
		for i in nb:
			for fl in k:
				# Satır: zemin katta kapı / vitrin / pencere; üst katlarda A ya da B çeşidi
				var row := 0
				if fl == 0:
					if fdoor > 0 and i == fdoor - 1:
						row = 2
					elif shop_ground:
						row = 1
				elif _hash(fl * 7.13 + seed) < 0.3 or (odd_b and i % 2 == 1) or (mid_b and fdoor > 0 and i == fdoor - 1):
					row = 7
				var y0 := ybot if fl == 0 else fl * KAT
				var y1 := (fl + 1) * KAT
				var p0 := a + dir * (i * cw)
				var p1 := a + dir * ((i + 1) * cw)
				var ps := [xf * (p0 + Vector3(0, y0, 0)), xf * (p1 + Vector3(0, y0, 0)), xf * (p1 + Vector3(0, y1, 0)), xf * (p0 + Vector3(0, y1, 0))]
				var vlo := v0 if fl == 0 else float(fl)
				_quad(sb, ps, [Vector2(i, vlo), Vector2(i + 1, vlo), Vector2(i + 1, fl + 1), Vector2(i, fl + 1)], basis * n, _cell_col(style, row))
				# Cephe derinliği (arka cephe sokağa bakmaz: yok)
				if fi != 1 and _sdet and (row == 0 or row == 1 or row == 7):
					var cf := xf * Transform3D(Basis(dir, Vector3.UP, n), p0 + Vector3(0, y1, 0))
					_facade_parts(cf, cw, style, row)
	var trim := _fc(style, 0, 3)
	# Kaide ve kat silmesi
	_ring(sb, xf, w, d, ybot, 0.35, 0.05, 0.12, trim)
	if k > 1:
		_ring(sb, xf, w, d, KAT - 0.06, KAT + 0.08, 0.07, 0.14, trim)
	var gable := String(it.get("cati", spec.get("cati", "duz"))) == "besik"
	if gable:
		_roof_gable(sb, xf, w, d, top, style)
		if _hash(seed * 3.1) < 0.6 or tur == "firin":                         # baca
			var cx := (_hash(seed * 5.7) - 0.5) * w * 0.5
			_box(_sd, xf, Vector3(cx, top + d * 0.25, -hd * 0.3), Vector3(0.6, d * 0.32 + 0.8, 0.6), _vc("#9c4a3a"))
			_box(_sd, xf, Vector3(cx, top + d * 0.25 + d * 0.16 + 0.45, -hd * 0.3), Vector3(0.75, 0.15, 0.75), _vc("#6f6f6f"))
	else:
		# Düz çatı: korkuluk duvarı (parapet), üstünde silme; içi çakıl
		_ring(sb, xf, w, d, top - 0.1, top + 0.55, 0.0, 0.22, _fc(style, 0, 5))
		_ring(sb, xf, w, d, top + 0.55, top + 0.7, 0.08, 0.32, trim)
		_ring(sb, xf, w, d, top - 0.25, top - 0.05, 0.12, 0.2, trim)
		var rp := [xf * Vector3(-hw, top + 0.05, -hd), xf * Vector3(hw, top + 0.05, -hd), xf * Vector3(hw, top + 0.05, hd), xf * Vector3(-hw, top + 0.05, hd)]
		_quad(sb, rp, [Vector2(0, 0), Vector2(w / 3.0, 0), Vector2(w / 3.0, d / 3.0), Vector2(0, d / 3.0)], Vector3.UP, _fc(style, 0, 4))
		_roof_props(xf, w, d, top, seed)
	# Çarpışma
	var body := _body("beton")
	_shape_box(body, Vector3(w, top - ybot + 0.7, d), xf * Transform3D(Basis(), Vector3(0, (top + 0.7 + ybot) * 0.5, 0)))
	# Özel binaların süsleri ve tabelaları
	var ad := String(it.get("ad", spec.get("tabela", ""))).to_upper()
	match tur:
		"muze":
			_deco_museum(xf, w, hd, top, body)
			_sign(ad, xf * Transform3D(Basis(), Vector3(0, top - 0.25, hd + 2.13)), 0.009)
		"sinema":
			_deco_cinema(xf, w, hw, hd, ad)
		"kafe":
			_deco_cafe(xf, w, hd, body)
			_sign_board(sb, xf, w, hd, trim, ad)
		"otel":
			_deco_hotel(xf, w, hd, k)
			_box(_sd, xf, Vector3(0, top + 1.5, hd - 0.6), Vector3(minf(w * 0.6, 6.0), 1.4, 0.15), _vc("#8c5a3c"))
			_sign(ad, xf * Transform3D(Basis(), Vector3(0, top + 1.5, hd - 0.52)), 0.016, Color(1.0, 0.9, 0.55))
			for sx: float in [-1.0, 1.0]:
				_box(_sd, xf, Vector3(sx * minf(w * 0.25, 2.4), top + 0.4, hd - 0.6), Vector3(0.1, 0.9, 0.1), _vc("#3a3a3a"))
		"kutuphane":
			_deco_library(xf, hd, body)
			_sign_board(sb, xf, w, hd, trim, ad)
		"firin":
			_sign_board(sb, xf, w, hd, trim, ad)
		_:
			if ad != "" and (bool(it.get("tabela_zorla", false)) or shop_ground):
				_sign_board(sb, xf, w, hd, trim, ad)
	_seed = 0.0


## Bir cephe hücresinin ayrıntıları (cephe.json): pencere pervazı ve alın, denizlik, tente,
## balkon ve korkuluk. cf: hücrenin sol üst köşesi; x sağa, y yukarı, z dışarı (m).
## Telefon için yalın: yalnız görünen yüzler (duvara yapışık ve arka yüzler yok).
func _facade_parts(cf: Transform3D, cw: float, style: int, row: int) -> void:
	var st: Dictionary = _cephe_data().stiller[style]
	var parts: Array = st.satirlar.get(str(row), [])
	if parts.is_empty():
		return
	var mx := cw / 32.0
	var my := KAT / 32.0
	var trim := _vc(String(st.pervaz))
	var trim_d := Color(trim.r * 0.86, trim.g * 0.86, trim.b * 0.86, trim.a)
	var acc := _vc(String(st.vurgu))
	acc = Color(acc.r * 0.8, acc.g * 0.8, acc.b * 0.8, 1.0)
	var balcony := false
	for pt in parts:
		if pt.t == "balkon":
			balcony = true
	for pt in parts:
		# Piksel dikdörtgeni -> metre (x0 sol, x1 sağ, yt üst, yb alt; y yukarı)
		var x0 := float(pt.x) * mx
		var x1 := (float(pt.x) + float(pt.w)) * mx
		var yt := -float(pt.y) * my
		var yb := -(float(pt.y) + float(pt.h)) * my
		match String(pt.t):
			"cam", "vitrin":
				var d := 0.08 if pt.t == "vitrin" else 0.06
				_frame(cf, x0, yb, x1, yt, mx, d, trim)
				if pt.t == "cam":
					_slab(cf, x0 - 2 * mx, yt + mx, x1 + 2 * mx, yt + mx + 2 * my, 0.11, trim_d)      # alın
				else:
					_slab(cf, x0 - mx, yb - mx - 2 * my, x1 + mx, yb - mx, 0.16, trim_d)             # vitrin altı
			"denizlik":
				_slab(cf, x0, yb, x1, yt, 0.16, trim_d)
			"tente":
				_awning(cf, x0, -yt, x1 - x0, Color(String(pt.renk)))
			"balkon":
				_slab(cf, x0, yb, x1, yt, 0.85, trim_d)
			"korkuluk":
				var z := 0.82 if balcony else 0.2
				_slab(cf, x0, yt - 0.05, x1, yt, z + 0.03, acc, z - 0.03)                         # tutamak
				var posts := maxi(int((x1 - x0) / 0.35), 2)
				for q in posts + 1:
					var px := x0 + (x1 - x0) * q / posts
					_flat(cf, px - 0.015, yb, px + 0.015, yt, z, acc)
				if balcony:
					for sx: float in [x0, x1]:
						_side(cf, sx, yt - 0.05, yt, 0.0, z, acc)


## Duvara dik düz dörtgen (z uzaklıkta, dışa bakar)
func _flat(cf: Transform3D, x0: float, y0: float, x1: float, y1: float, z: float, col: Color) -> void:
	_quad(_sdet, [cf * Vector3(x0, y0, z), cf * Vector3(x1, y0, z), cf * Vector3(x1, y1, z), cf * Vector3(x0, y1, z)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(0, 0, 1), col)


## Yanda dik şerit (x sabit; y0..y1, z0..z1), dışa (x yönüne) bakar
func _side(cf: Transform3D, x: float, y0: float, y1: float, z0: float, z1: float, col: Color, nx := 1.0) -> void:
	_quad(_sdet, [cf * Vector3(x, y0, z0), cf * Vector3(x, y0, z1), cf * Vector3(x, y1, z1), cf * Vector3(x, y1, z0)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(nx, 0, 0), col)


## Duvardan çıkan ince levha (denizlik, alın, balkon): ön, üst ve alt yüz
func _slab(cf: Transform3D, x0: float, y0: float, x1: float, y1: float, z1: float, col: Color, z0 := 0.0) -> void:
	_flat(cf, x0, y0, x1, y1, z1, col)
	var top := Color(col.r * 1.06, col.g * 1.06, col.b * 1.06, col.a)
	_quad(_sdet, [cf * Vector3(x0, y1, z0), cf * Vector3(x1, y1, z0), cf * Vector3(x1, y1, z1), cf * Vector3(x0, y1, z1)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(0, 1, 0), top)
	var bot := Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, col.a)
	_quad(_sdet, [cf * Vector3(x0, y0, z0), cf * Vector3(x1, y0, z0), cf * Vector3(x1, y0, z1), cf * Vector3(x0, y0, z1)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(0, -1, 0), bot)


## Pencere pervazı: camın çevresinde t kalın, d çıkıntılı çerçeve; ön yüz ve camın kenarındaki
## iç derinlik (cam içeride, gölgeli kenarlarla)
func _frame(cf: Transform3D, x0: float, y0: float, x1: float, y1: float, t: float, d: float, col: Color) -> void:
	_flat(cf, x0 - t, y1, x1 + t, y1 + t, d, col)
	_flat(cf, x0 - t, y0 - t, x1 + t, y0, d, col)
	_flat(cf, x0 - t, y0, x0, y1, d, col)
	_flat(cf, x1, y0, x1 + t, y1, d, col)
	var inner := Color(col.r * 0.72, col.g * 0.72, col.b * 0.72, col.a)
	_side(cf, x0, y0, y1, 0.0, d, inner, 1.0)
	_side(cf, x1, y0, y1, 0.0, d, inner, -1.0)
	_quad(_sdet, [cf * Vector3(x0, y1, 0.0), cf * Vector3(x1, y1, 0.0), cf * Vector3(x1, y1, d), cf * Vector3(x0, y1, d)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(0, -1, 0), Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, col.a))
	_quad(_sdet, [cf * Vector3(x0, y0, 0.0), cf * Vector3(x1, y0, 0.0), cf * Vector3(x1, y0, d), cf * Vector3(x0, y0, d)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(0, 1, 0), Color(col.r * 0.95, col.g * 0.95, col.b * 0.95, col.a))


## Tente: duvardan dışarı eğik, renkli ve krem şeritli; önünde sarkan saçak (şerit başına 2 yüz)
func _awning(cf: Transform3D, x: float, ytop: float, w: float, col: Color) -> void:
	var out := 0.95
	var drop := 0.5
	var n := maxi(int(w / 0.28), 2)
	var sw := w / n
	var cream := Color(0.98, 0.96, 0.92)
	var y0 := -ytop
	var slope_n := (cf.basis * Vector3(0, out, drop)).normalized()
	for i in n:
		var c := col if i % 2 == 0 else cream
		var xa := x + i * sw
		var xb := xa + sw
		_quad(_sdet, [cf * Vector3(xa, y0, 0.0), cf * Vector3(xb, y0, 0.0), cf * Vector3(xb, y0 - drop, out), cf * Vector3(xa, y0 - drop, out)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], slope_n, c)
		_flat(cf, xa, y0 - drop - 0.16, xb, y0 - drop, out, c)
	# Alt yüz tek parça (gölgeli)
	var dark := Color(col.r * 0.55, col.g * 0.55, col.b * 0.55)
	_quad(_sdet, [cf * Vector3(x, y0, 0.0), cf * Vector3(x + w, y0, 0.0), cf * Vector3(x + w, y0 - drop, out), cf * Vector3(x, y0 - drop, out)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], -slope_n, dark)
	for sx: float in [x, x + w]:
		var t := [cf * Vector3(sx, y0, 0.0), cf * Vector3(sx, y0 - drop, out), cf * Vector3(sx, y0 - drop - 0.16, out)]
		_tri(_sdet, t, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], cf.basis * Vector3(1 if sx > x else -1, 0, 0), col)


## Tabela: zemin katın üstünde levha ve yazı
func _sign_board(sb: SurfaceTool, xf: Transform3D, w: float, hd: float, trim: Color, text: String) -> void:
	if text == "":
		return
	_box(sb, xf, Vector3(0, KAT + 0.45, hd + 0.08), Vector3(minf(w * 0.8, 7.0), 0.6, 0.12), trim)
	_sign(text, xf * Transform3D(Basis(), Vector3(0, KAT + 0.45, hd + 0.16)), 0.006)


func _sign(text: String, xf: Transform3D, px: float, col := Color(1.0, 0.92, 0.6)) -> void:
	if text == "":
		return
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 64
	lb.outline_size = 12
	lb.modulate = col
	lb.outline_modulate = Color(0.1, 0.1, 0.14)
	lb.pixel_size = px
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	lb.transform = xf
	_built.add_child(lb)


## Düz çatıda klima, su deposu, havalandırma (binaya göre değişir)
func _roof_props(xf: Transform3D, w: float, d: float, top: float, seed: float) -> void:
	var n := int(_hash(seed * 1.7) * 3.0)
	for i in n:
		var px := (_hash(seed * 2.3 + i) - 0.5) * (w - 2.0)
		var pz := (_hash(seed * 4.1 + i) - 0.5) * (d - 2.0)
		if _hash(seed + i * 9.0) < 0.6:
			_box(_sd, xf, Vector3(px, top + 0.4, pz), Vector3(0.9, 0.7, 0.6), _vc("#dcdcd6"))
			_box(_sd, xf, Vector3(px, top + 0.42, pz + 0.31), Vector3(0.5, 0.5, 0.02), _vc("#7b7d80"))
		else:
			_box(_sd, xf, Vector3(px, top + 0.25, pz), Vector3(0.12, 0.6, 0.12), _vc("#6f6f6f"))
			_box(_sd, xf, Vector3(px, top + 0.85, pz), Vector3(1.1, 1.0, 1.1), _vc("#f2f0ea"))
	if _hash(seed * 7.7) < 0.35:
		_box(_sd, xf, Vector3((_hash(seed * 8.8) - 0.5) * (w - 2.0), top + 0.6, -d * 0.25), Vector3(0.18, 1.2, 0.18), _vc("#9a9a9a"))


## Müze: geniş basamaklar, sütunlu giriş, saçaklık ve üçgen alınlık
func _deco_museum(xf: Transform3D, w: float, hd: float, top: float, body: StaticBody3D) -> void:
	var stone := _vc("#e9e3d6")
	var steps := 3
	for i in steps:
		var y1 := (i + 1) * 0.18
		var depth := 2.6 - i * 0.6
		_box(_sd, xf, Vector3(0, (y1 - 0.3) * 0.5, hd + depth * 0.5), Vector3(w * 0.78 - i * 0.4, y1 + 0.3, depth), _vc("#d8d1c3"))
	_shape_box(body, Vector3(w * 0.78, 0.84, 2.6), xf * Transform3D(Basis(), Vector3(0, 0.12, hd + 1.3)))
	var floor_y := steps * 0.18
	var n := 6
	var zc := hd + 1.75
	for i in n:
		var x := -w * 0.34 + w * 0.68 * i / (n - 1)
		_box(_sd, xf, Vector3(x, floor_y + 0.12, zc), Vector3(0.85, 0.24, 0.85), stone)
		_box(_sd, xf, Vector3(x, (floor_y + top - 0.6) * 0.5, zc), Vector3(0.55, top - 0.6 - floor_y, 0.55), _vc("#f3efe6"))
		_box(_sd, xf, Vector3(x, top - 0.72, zc), Vector3(0.85, 0.24, 0.85), stone)
		_shape_box(body, Vector3(0.55, top - floor_y, 0.55), xf * Transform3D(Basis(), Vector3(x, (floor_y + top) * 0.5, zc)))
	# Saçaklık (kirişleme) ve alınlık
	_box(_sd, xf, Vector3(0, top - 0.25, hd + 1.05), Vector3(w * 0.8, 0.7, 2.2), stone)
	var pw := w * 0.42
	var y0 := top + 0.1
	var ph := 1.6
	for zz: float in [hd - 0.05, hd + 2.15]:
		var n2 := Vector3(0, 0, 1) if zz > hd else Vector3(0, 0, -1)
		_tri(_sd, [xf * Vector3(-pw, y0, zz), xf * Vector3(pw, y0, zz), xf * Vector3(0, y0 + ph, zz)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], xf.basis * n2, stone)
	for sg: float in [-1.0, 1.0]:
		var nn: Vector3 = (xf.basis * Vector3(sg * ph, pw, 0)).normalized()
		_quad(_sd, [xf * Vector3(sg * pw, y0, hd - 0.05), xf * Vector3(sg * pw, y0, hd + 2.15), xf * Vector3(0, y0 + ph, hd + 2.15), xf * Vector3(0, y0 + ph, hd - 0.05)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nn, _vc("#cfc7b6"))


## Sinema: ampullü markiz, üstünde adı; köşede dikey bayrak tabela
func _deco_cinema(xf: Transform3D, w: float, hw: float, hd: float, ad: String) -> void:
	var mw := minf(w * 0.75, 9.0)
	var my := KAT + 0.6
	_box(_sd, xf, Vector3(0, my, hd + 1.1), Vector3(mw, 0.9, 2.2), _vc("#5c1a24"))
	_box(_sd, xf, Vector3(0, my + 0.5, hd + 1.1), Vector3(mw + 0.1, 0.12, 2.3), _vc("#f0c94e"))
	_box(_sd, xf, Vector3(0, my - 0.5, hd + 1.1), Vector3(mw + 0.1, 0.12, 2.3), _vc("#f0c94e"))
	var bulb := _vc("#fff3a0", 0.9)
	var nb := int(mw / 0.35)
	for i in nb + 1:
		var x := -mw * 0.5 + mw * i / nb
		_box(_sd, xf, Vector3(x, my - 0.62, hd + 2.25), Vector3(0.1, 0.1, 0.1), bulb)
		_box(_sd, xf, Vector3(x, my + 0.62, hd + 2.25), Vector3(0.1, 0.1, 0.1), bulb)
	_sign(ad, xf * Transform3D(Basis(), Vector3(0, my, hd + 2.22)), 0.0085, Color(1.0, 0.95, 0.7))
	# Bayrak tabela (köşede, iki yana bakar)
	var bx := hw - 0.4
	_box(_sd, xf, Vector3(bx, KAT * 2 - 0.2, hd + 0.75), Vector3(0.35, 3.6, 1.5), _vc("#7a2632"))
	for i in 9:
		_box(_sd, xf, Vector3(bx, KAT * 2 - 1.8 + i * 0.45, hd + 1.52), Vector3(0.12, 0.12, 0.06), bulb)
	var letters := "\n".join(Array(ad.split("")))
	for sg: float in [-1.0, 1.0]:
		_sign(letters, xf * Transform3D(Basis(Vector3.UP, sg * PI * 0.5), Vector3(bx + sg * 0.19, KAT * 2 - 0.2, hd + 0.75)), 0.0075, Color(1.0, 0.85, 0.35))


## Kafe: kaldırımda şemsiyeli masalar ve sandalyeler
func _deco_cafe(xf: Transform3D, w: float, hd: float, body: StaticBody3D) -> void:
	var cols := ["#e6866f", "#7cc6b0", "#f0c05a"]
	for i in 3:
		var x := (i - 1) * minf(w * 0.32, 2.6)
		var z := hd + 1.7
		_box(_sd, xf, Vector3(x, 0.38, z), Vector3(0.08, 0.76, 0.08), _vc("#3a3a3a"))
		_box(_sd, xf, Vector3(x, 0.78, z), Vector3(0.8, 0.05, 0.8), _vc("#8a5a3c"))
		for sx: float in [-1.0, 1.0]:
			_box(_sd, xf, Vector3(x + sx * 0.62, 0.23, z), Vector3(0.38, 0.46, 0.38), _vc("#6b8f71"))
			_box(_sd, xf, Vector3(x + sx * 0.8, 0.6, z), Vector3(0.05, 0.7, 0.38), _vc("#6b8f71"))
		_box(_sd, xf, Vector3(x, 1.5, z), Vector3(0.05, 1.5, 0.05), _vc("#d9d4c8"))
		# Şemsiye: dört üçgen, iki renk dönüşümlü
		var apex := xf * Vector3(x, 2.55, z)
		var r := 1.05
		var corners := [Vector3(-r, 2.1, -r), Vector3(r, 2.1, -r), Vector3(r, 2.1, r), Vector3(-r, 2.1, r)]
		for q in 4:
			var a: Vector3 = xf * (Vector3(x, 0, z) + corners[q])
			var b: Vector3 = xf * (Vector3(x, 0, z) + corners[(q + 1) % 4])
			var nn := (b - a).cross(apex - a).normalized()
			if nn.y < 0.0:
				nn = -nn
			var col := _vc(cols[i]) if q % 2 == 0 else _vc("#fff3e0")
			_tri(_sd, [a, b, apex], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nn, col)
			_tri(_sd, [a, b, apex], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], -nn, col)
		_shape_box(body, Vector3(0.8, 0.8, 0.8), xf * Transform3D(Basis(), Vector3(x, 0.4, z)))


## Otel: her katta boydan boya balkon ve korkuluk
func _deco_hotel(xf: Transform3D, w: float, hd: float, k: int) -> void:
	for f in range(1, k):
		var y := f * KAT
		_box(_sd, xf, Vector3(0, y - 0.05, hd + 0.5), Vector3(w - 0.6, 0.15, 1.0), _vc("#efe4cf"))
		_box(_sd, xf, Vector3(0, y + 0.95, hd + 0.97), Vector3(w - 0.6, 0.06, 0.06), _vc("#3a3a3a"))
		var n := int((w - 0.6) / 0.5)
		for i in n + 1:
			var x := -(w - 0.6) * 0.5 + (w - 0.6) * i / n
			_box(_sd, xf, Vector3(x, y + 0.5, hd + 0.97), Vector3(0.04, 0.9, 0.04), _vc("#3a3a3a"))


## Kütüphane: basamaklar ve kapının iki yanında sütun
func _deco_library(xf: Transform3D, hd: float, body: StaticBody3D) -> void:
	for i in 2:
		var y1 := (i + 1) * 0.17
		var depth := 1.8 - i * 0.6
		_box(_sd, xf, Vector3(0, (y1 - 0.3) * 0.5, hd + depth * 0.5), Vector3(4.2 - i * 0.4, y1 + 0.3, depth), _vc("#d8d1c3"))
	_shape_box(body, Vector3(4.2, 0.64, 1.8), xf * Transform3D(Basis(), Vector3(0, 0.02, hd + 0.9)))
	for sx: float in [-1.0, 1.0]:
		_box(_sd, xf, Vector3(sx * 1.75, 1.6, hd + 0.35), Vector3(0.45, 3.2, 0.45), _vc("#efe6d5"))
		_box(_sd, xf, Vector3(sx * 1.75, 3.25, hd + 0.35), Vector3(0.65, 0.2, 0.65), _vc("#e2d6bf"))


## Beşik çatı: mahya uzun kenar boyunca, kiremit; alınlıklar düz duvar
func _roof_gable(sb: SurfaceTool, xf: Transform3D, w: float, d: float, top: float, style: int) -> void:
	var along_x := w >= d
	var L := w if along_x else d          # mahya boyu
	var S := d if along_x else w          # açıklık
	var rh := S * 0.32
	var ov := 0.35
	var col := _fc(style, 0, 6)
	var plain := _fc(style, 0, 5)
	var ax := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)     # mahya yönü
	var sx := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)     # eğim yönü (yatay)
	var slope_len := sqrt((S * 0.5 + ov) * (S * 0.5 + ov) + rh * rh)
	for sg: float in [-1.0, 1.0]:
		var eave := sx * sg * (S * 0.5 + ov) + Vector3(0, top - ov * rh / (S * 0.5), 0)
		var ridge := Vector3(0, top + rh, 0)
		var e0 := eave - ax * (L * 0.5 + ov)
		var e1 := eave + ax * (L * 0.5 + ov)
		var r0 := ridge - ax * (L * 0.5 + ov)
		var r1 := ridge + ax * (L * 0.5 + ov)
		var n: Vector3 = (xf.basis * (sx * sg * rh + Vector3.UP * (S * 0.5))).normalized()
		var ps := [xf * e0, xf * e1, xf * r1, xf * r0]
		var uvs := [Vector2(0, 0), Vector2(L / 3.0, 0), Vector2(L / 3.0, slope_len / 3.0), Vector2(0, slope_len / 3.0)]
		_quad(sb, ps, uvs, n, col)
		_quad(sb, ps, uvs, -n, col)      # saçak altı
	# Alınlıklar (üçgen duvar)
	for sg: float in [-1.0, 1.0]:
		var base := ax * sg * L * 0.5
		var p0 := base - sx * S * 0.5 + Vector3(0, top, 0)
		var p1 := base + sx * S * 0.5 + Vector3(0, top, 0)
		var p2 := base + Vector3(0, top + rh, 0)
		_tri(sb, [xf * p0, xf * p1, xf * p2], [Vector2(0, 0), Vector2(S / 3.0, 0), Vector2(S / 6.0, rh / 3.0)], xf.basis * (ax * sg), plain)


# ---------- Dükkân ----------

func _build_shop(it: Dictionary, sb: SurfaceTool) -> void:
	var tur := String(it.get("tur", "bakkal"))
	var tp: Dictionary = DUKKAN_TURLERI.get(tur, DUKKAN_TURLERI.bakkal)
	var c := v2(it.p)
	var basis := _yaw(it)
	var ad := String(it.get("ad", tp.ad)).to_upper()
	if not tp.girilebilir:
		# Şimdilik dıştan: vitrinli bina ve tabela (kapı ortası p'de; bina arkaya uzanır)
		var back: Vector3 = basis * Vector3(0, 0, -float(tp.d) * 0.5)
		var b := {"p": [c.x + back.x, c.y + back.z], "r": it.get("r", 0.0), "w": tp.w, "d": tp.d, "k": tp.k, "s": tp.stil,
			"cati": "duz", "zemin": "dukkan", "id": it.id, "ad": ad, "tabela_zorla": true}
		if it.has("_y"):
			b["_y"] = it._y
		_build_bina(b, sb)
		return
	var id := int(it.id)
	var y: float = float(it["_y"]) if it.has("_y") else ground(c.x, c.y, false)
	var key := JSON.stringify([it.p, it.get("r", 0.0), tur, ad, snappedf(y, 0.01)])
	if _shops.has(id) and _shops[id].key == key and is_instance_valid(_shops[id].node):
		return
	if _shops.has(id) and is_instance_valid(_shops[id].node):
		_shops[id].node.queue_free()
	var shop := Dukkan.new()
	shop.name = "Dukkan_%d" % id
	shop.player = player
	shop.follow_cam = follow_cam
	shop.ui_parent = ui_parent
	shop.ad = ad
	shop.transform = Transform3D(basis, Vector3(c.x, y, c.y))
	add_child(shop)
	if look and look.has_method("add_root"):
		look.add_root(shop)
	_shops[id] = {"node": shop, "key": key}


# ---------- Yükselti ----------

func _build_platform(it: Dictionary, sb: SurfaceTool, sc: SurfaceTool, sk: SurfaceTool) -> void:
	var c := v2(it.p)
	var basis := _yaw(it)
	var w := float(it.w)
	var d := float(it.d)
	var top := float(it._top)
	var style := clampi(int(it.get("s", 7)), 0, STIL_ADLARI.size() - 1)
	var ylow := top
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = basis * Vector3(s.x * w * 0.5, 0, s.y * d * 0.5)
		ylow = minf(ylow, ground(c.x + p.x, c.y + p.z, false))
	var xf := Transform3D(basis, Vector3(c.x, top, c.y))
	var yb := ylow - top - 0.5
	var hw := w * 0.5
	var hd := d * 0.5
	# Yan duvarlar: düz duvar dokusu (taş / beton), metre başına
	var faces := [
		[Vector3(0, 0, 1), Vector3(-hw, 0, hd), Vector3(hw, 0, hd), w],
		[Vector3(0, 0, -1), Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), w],
		[Vector3(1, 0, 0), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), d],
		[Vector3(-1, 0, 0), Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), d],
	]
	for f in faces:
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var L: float = f[3]
		var ps := [xf * (a + Vector3(0, yb, 0)), xf * (b + Vector3(0, yb, 0)), xf * b, xf * a]
		_quad(sb, ps, [Vector2(0, yb / 3.0), Vector2(L / 3.0, yb / 3.0), Vector2(L / 3.0, 0), Vector2(0, 0)], basis * f[0], _fc(style, 0, 5))
	# Üst: Arnavut kaldırımı; kenarda beton harpuşta (dışa taşan, yüzeyle aynı hizada)
	var tp := [xf * Vector3(-hw, 0.0, -hd), xf * Vector3(hw, 0.0, -hd), xf * Vector3(hw, 0.0, hd), xf * Vector3(-hw, 0.0, hd)]
	_quad(sc, tp, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, Color.WHITE)
	_ring(sk, xf, w, d, -0.14, 0.012, 0.06, 0.26, Color.WHITE)
	var body := _body("arnavut")
	_shape_box(body, Vector3(w, -yb, d), xf * Transform3D(Basis(), Vector3(0, yb * 0.5, 0)))
	# Kenarlar grind (beton)
	var cs := [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]
	for i in 4:
		_rail(xf * cs[i] + Vector3(0, 0.01, 0), xf * cs[(i + 1) % 4] + Vector3(0, 0.01, 0), "beton")


# ---------- Merdiven ----------

func _build_stairs(it: Dictionary, sk: SurfaceTool, sm: SurfaceTool) -> void:
	var a2 := v2(it.a)
	var b2 := v2(it.b)
	var L := a2.distance_to(b2)
	if L < 0.5:
		return
	var w := float(it.get("w", 2.4))
	var ha := ground(a2.x, a2.y)
	var hb := ground(b2.x, b2.y)
	# Alçaktan yükseğe
	if hb < ha:
		var t2 := a2
		a2 = b2
		b2 = t2
		var th := ha
		ha = hb
		hb = th
	var dir := (b2 - a2) / L
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.y))       # yerel +Z merdiven yönü
	var xf := Transform3D(basis, Vector3(a2.x, ha, a2.y))
	var dh := hb - ha
	var n := maxi(int(ceil(dh / 0.18)), 1)
	var step_d := L / n
	var bottom := -0.5
	for i in n:
		var z0 := i * step_d
		var y1 := dh * (i + 1) / n
		_box(sk, xf, Vector3(0, (bottom + y1) * 0.5, z0 + (L - z0) * 0.5), Vector3(w, y1 - bottom, L - z0), Color.WHITE)
	# Çarpışma: basamak burunlarından geçen eğik rampa (kaykay takılmadan kayar)
	var A3 := Vector3(a2.x, ha, a2.y)
	var B3 := Vector3(b2.x, hb, b2.y)
	var d3 := (B3 - A3).normalized()
	var side := d3.cross(Vector3.UP).normalized()
	var up := side.cross(d3).normalized()
	var body := _body("beton")
	var rb := Basis(side, up, d3)
	_shape_box(body, Vector3(w, 0.3, A3.distance_to(B3) + 0.2), Transform3D(rb, (A3 + B3) * 0.5 - up * 0.15))
	# Yanları dolu blok (alttan bakınca boşluk olmasın)
	_shape_box(body, Vector3(w, 0.5, L), Transform3D(basis, Vector3(a2.x, ha - 0.25, a2.y) + basis * Vector3(0, 0, L * 0.5)))
	if bool(it.get("korkuluk", true)):
		for sg: float in [-1.0, 1.0]:
			var off := basis * Vector3(sg * (w * 0.5 - 0.12), 0, 0)
			var p0 := A3 + off + Vector3.UP * 0.9
			var p1 := B3 + off + Vector3.UP * 0.9
			_bar(sm, p0, p1, 0.07)
			var posts := maxi(int(ceil(L / 1.6)), 1)
			for k in posts + 1:
				var t := float(k) / posts
				var base := A3.lerp(B3, t) + off
				_post(sm, base, 0.9)
			_rail(p0 + Vector3.UP * 0.035, p1 + Vector3.UP * 0.035, "metal")


## İki nokta arasında kare kesitli çubuk
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, t: float) -> void:
	var L := a.distance_to(b)
	if L < 0.01:
		return
	var z := (b - a) / L
	var x := z.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := x.cross(z).normalized()
	var xf := Transform3D(Basis(x, y, z), (a + b) * 0.5)
	_box(st, xf, Vector3.ZERO, Vector3(t, t, L), Color.WHITE)


static func _post(st: SurfaceTool, base: Vector3, h: float) -> void:
	_box(st, Transform3D(Basis(), base), Vector3(0, h * 0.5 - 0.05, 0), Vector3(0.06, h + 0.1, 0.06), Color.WHITE)


# ---------- Korkuluk ----------

func _build_railing(it: Dictionary, sm: SurfaceTool) -> void:
	var pts: Array = it.pts
	if pts.size() < 2:
		return
	var h := float(it.get("h", 0.9))
	var body := _body("metal")
	var tops: Array[Vector3] = []
	for q in pts:
		var p := v2(q)
		tops.append(Vector3(p.x, ground(p.x, p.y) + h, p.y))
	for i in pts.size() - 1:
		var a := tops[i]
		var b := tops[i + 1]
		_bar(sm, a, b, 0.07)
		_bar(sm, a - Vector3.UP * h * 0.5, b - Vector3.UP * h * 0.5, 0.035)
		var L := Vector2(a.x - b.x, a.z - b.z).length()
		var posts := maxi(int(ceil(L / 1.4)), 1)
		for k in posts:
			var p := a.lerp(b, float(k) / posts)
			_post(sm, p - Vector3.UP * h, h)
		var mid := (a + b) * 0.5 - Vector3.UP * h * 0.5
		var z := Vector3(b.x - a.x, 0, b.z - a.z)
		if z.length() > 0.01:
			var bs := Basis(Vector3.UP, atan2(z.x, z.z))
			_shape_box(body, Vector3(0.1, h + 0.1, z.length()), Transform3D(bs, mid))
		_rail(a + Vector3.UP * 0.035, b + Vector3.UP * 0.035, "metal")
	_post(sm, tops[tops.size() - 1] - Vector3.UP * h, h)
