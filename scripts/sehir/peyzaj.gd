class_name Peyzaj
extends Node3D
## Peyzaj: ağaçlar, çalılar, ot öbekleri, kayalar (assets/ada/peyzaj.json; modeller
## assets/peyzaj/peyzaj.glb: tools/blender/peyzaj_build.py; ilk yerleşim tools/sehir/peyzaj_uret.py).
##
## Çizim ucuz olsun diye ada 64 m'lik parsellere bölünür. Her parselde:
##   - yakın: her tür TEK bir MultiMesh (ayrıntılı model, rüzgârda salınır, ağaçlar gölge düşürür)
##   - uzak: parseldeki her şeyin çok az üçgenli uzak modelleri tek bir meshte birleşik (tek çizim)
## Yakın modeller uzak meshe bağlıdır (visibility_parent): kamera parsele SWITCH mesafesinden
## yakınsa yakınlar, uzaksa yalnız uzak mesh çizilir; ikisi aynı anda çizilmez, arada boşluk kalmaz.
## Seçimi motor yapar, işlemci her kare bir şey hesaplamaz. Uzak meshler açılışta birkaç karede bir
## parça parça kurulur (açılışı geciktirmez). Ot öbekleri yalnız yakında (OT_MESAFE).
## Ağaç gövdeleri, büyük kayalar ve çit çarpışır (katman Sehir.LAYER); çalı ve otun içinden geçilir.
## Şehir editörü ekler / siler (add, remove_at_point); kayıt assets/ada/peyzaj.json.

static var instance: Peyzaj

const GLB := "res://assets/peyzaj/peyzaj.glb"
const DATA_PATH := "res://assets/ada/peyzaj.json"
const SHADER := preload("res://shaders/peyzaj.gdshader")
const CHUNK := 64.0
## Parselin (uzak meshin) ortasına bu mesafeden yakınken ayrıntılı modeller çizilir
const SWITCH := 115.0
const UZAK_SON := 600.0
const OT_MESAFE := 55.0
## Uzak meshler açılıştan sonra kare kare kurulur: bir karede en çok bu kadar süre (mikrosaniye)
const FAR_BUDGET_US := 2500

## Türler. r: gövde çarpışma yarıçapı (0: yok), h: çarpışma yüksekliği, kutu: çarpışma kutusu (çit),
## golge: gölge düşürür, renk: yaprak rengi çeşitlemesi (0: yok), ot: yalnız yakında çizilir.
const TURLER := {
	"cinar_1": {"ad": "Çınar", "grup": "Ağaç", "r": 0.32, "h": 3.0, "golge": true, "renk": 0.09},
	"cinar_2": {"ad": "Çınar (küçük)", "grup": "Ağaç", "r": 0.28, "h": 3.0, "golge": true, "renk": 0.09},
	"cinar_3": {"ad": "Çınar (büyük)", "grup": "Ağaç", "r": 0.36, "h": 3.0, "golge": true, "renk": 0.09},
	"ihlamur": {"ad": "Ihlamur", "grup": "Ağaç", "r": 0.3, "h": 3.0, "golge": true, "renk": 0.08},
	"erguvan": {"ad": "Erguvan", "grup": "Ağaç", "r": 0.24, "h": 2.5, "golge": true, "renk": 0.06},
	"zeytin": {"ad": "Zeytin", "grup": "Ağaç", "r": 0.26, "h": 2.5, "golge": true, "renk": 0.07},
	"fistikcami_1": {"ad": "Fıstık çamı", "grup": "Ağaç", "r": 0.3, "h": 4.0, "golge": true, "renk": 0.07},
	"fistikcami_2": {"ad": "Fıstık çamı (küçük)", "grup": "Ağaç", "r": 0.28, "h": 4.0, "golge": true, "renk": 0.07},
	"koknar_1": {"ad": "Köknar", "grup": "Ağaç", "r": 0.28, "h": 3.0, "golge": true, "renk": 0.07},
	"koknar_2": {"ad": "Köknar (küçük)", "grup": "Ağaç", "r": 0.24, "h": 3.0, "golge": true, "renk": 0.07},
	"koknar_3": {"ad": "Köknar (büyük)", "grup": "Ağaç", "r": 0.32, "h": 3.0, "golge": true, "renk": 0.07},
	"servi_1": {"ad": "Servi", "grup": "Ağaç", "r": 0.4, "h": 3.0, "golge": true, "renk": 0.05},
	"servi_2": {"ad": "Servi (küçük)", "grup": "Ağaç", "r": 0.35, "h": 3.0, "golge": true, "renk": 0.05},
	"palmiye_1": {"ad": "Palmiye", "grup": "Ağaç", "r": 0.24, "h": 3.0, "golge": true, "renk": 0.06},
	"palmiye_2": {"ad": "Palmiye (kısa)", "grup": "Ağaç", "r": 0.24, "h": 3.0, "golge": true, "renk": 0.06},
	"cali_1": {"ad": "Çalı", "grup": "Çalı", "golge": false, "renk": 0.1},
	"cali_2": {"ad": "Çalı (büyük)", "grup": "Çalı", "golge": false, "renk": 0.1},
	"cali_3": {"ad": "Çalı (küçük)", "grup": "Çalı", "golge": false, "renk": 0.1},
	"cali_pembe": {"ad": "Çiçekli çalı (pembe)", "grup": "Çalı", "golge": false, "renk": 0.07},
	"cali_sari": {"ad": "Çiçekli çalı (sarı)", "grup": "Çalı", "golge": false, "renk": 0.07},
	"cali_beyaz": {"ad": "Çiçekli çalı (beyaz)", "grup": "Çalı", "golge": false, "renk": 0.07},
	"cali_grup_1": {"ad": "Çalı öbeği 1", "grup": "Çalı", "golge": false, "renk": 0.08},
	"cali_grup_2": {"ad": "Çalı öbeği 2 (çiçekli)", "grup": "Çalı", "golge": false, "renk": 0.08},
	"cali_grup_3": {"ad": "Çalı öbeği 3 (çiçekli)", "grup": "Çalı", "golge": false, "renk": 0.08},
	"cit": {"ad": "Çit (2 m)", "grup": "Çalı", "kutu": Vector3(2.0, 0.9, 0.7), "golge": false, "renk": 0.05},
	"ot_1": {"ad": "Ot öbeği", "grup": "Ot / kaya", "golge": false, "renk": 0.1, "ot": true},
	"ot_2": {"ad": "Ot öbeği (uzun)", "grup": "Ot / kaya", "golge": false, "renk": 0.1, "ot": true},
	"kaya_1": {"ad": "Kaya", "grup": "Ot / kaya", "r": 0.75, "h": 1.0, "golge": true, "renk": 0.0},
	"kaya_2": {"ad": "Kaya (büyük)", "grup": "Ot / kaya", "r": 1.3, "h": 1.6, "golge": true, "renk": 0.0},
	"kaya_3": {"ad": "Kaya (küçük)", "grup": "Ot / kaya", "golge": true, "renk": 0.0},
}

var look: Node
## [tur, x, z, yön (derece), ölçek]
var items: Array = []

var _meshes := {}               # tur -> [yakın Mesh, uzak meshin yüzey dizileri ya da null]
var _mat: ShaderMaterial
var _mat_far: ShaderMaterial
var _chunks := {}               # Vector2i -> {root, near: [MultiMeshInstance3D], far, list, center}
var _far_queue: Array[Vector2i] = []
var _dirty := {}
var _ready_done := false
var _y_cache := {}              # öğe dizisi (aynı nesne) -> zemin yüksekliği
var _far_us := 0                # ölçüm: uzak meshlere harcanan toplam / en uzun süre (mikrosaniye)
var _far_max_us := 0


func _ready() -> void:
	instance = self
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat_far = ShaderMaterial.new()
	_mat_far.shader = SHADER
	_mat_far.set_shader_parameter("wind_strength", 0.0)
	var scene: PackedScene = load(GLB)
	if scene:
		var root := scene.instantiate()
		for tur in TURLER:
			var a := root.find_child(tur, true, false) as MeshInstance3D
			var b := root.find_child(tur + "_uzak", true, false) as MeshInstance3D
			if a:
				_meshes[tur] = [a.mesh, b.mesh.surface_get_arrays(0) if b and not TURLER[tur].get("ot", false) else null]
		root.free()
	# Görünüm ayarları (toon, köşe oturtma) iki ortak malzemeye: görünmez iki tutucu düğüm üzerinden
	for m in [_mat, _mat_far]:
		var holder := MeshInstance3D.new()
		holder.name = "MalzemeTutucu"
		holder.visible = false
		holder.material_override = m
		add_child(holder)
	if look and look.has_method("add_root"):
		look.add_root(self)
	load_data()
	# Zemin ışınları için fizik dünyası hazır olsun
	await get_tree().physics_frame
	await get_tree().physics_frame
	build_all()
	_ready_done = true
	if Sehir.instance and Sehir.instance.has_signal("rebuilt"):
		Sehir.instance.rebuilt.connect(_on_city_rebuilt)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ---------- Veri ----------

func load_data() -> void:
	items.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if j is Dictionary and j.get("items") is Array:
		for it in j.items:
			if it is Array and it.size() >= 5 and TURLER.has(String(it[0])):
				items.append([String(it[0]), float(it[1]), float(it[2]), float(it[3]), float(it[4])])


func save() -> bool:
	var out := []
	for it in items:
		out.append([it[0], snappedf(it[1], 0.01), snappedf(it[2], 0.01), snappedf(it[3], 0.1), snappedf(it[4], 0.01)])
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"v": 1, "items": out}))
	return true


## Geri alma için: bütün liste metin olarak
func snapshot() -> String:
	return JSON.stringify(items)


func restore(s: String) -> void:
	var j: Variant = JSON.parse_string(s)
	if not (j is Array):
		return
	items.clear()
	for it in j:
		items.append([String(it[0]), float(it[1]), float(it[2]), float(it[3]), float(it[4])])
	_y_cache.clear()
	build_all()


func add(tur: String, x: float, z: float, rot := 0.0, scale := 1.0) -> void:
	if not TURLER.has(tur):
		return
	items.append([tur, x, z, rot, scale])
	_dirty[_key(x, z)] = true


## Noktaya en yakın öğeyi (yarıçap içinde) ya da yarıçaptaki hepsini (all) sil; silinen sayısı
func remove_at_point(x: float, z: float, radius: float, all := false) -> int:
	var best := -1
	var best_d := radius * radius
	var gone: Array[int] = []
	for i in items.size():
		var it: Array = items[i]
		var dd: float = (it[1] - x) * (it[1] - x) + (it[2] - z) * (it[2] - z)
		if dd <= radius * radius:
			if all:
				gone.append(i)
			elif dd <= best_d:
				best_d = dd
				best = i
	if not all and best >= 0:
		gone.append(best)
	gone.sort()
	gone.reverse()
	for i in gone:
		var it: Array = items[i]
		_dirty[_key(it[1], it[2])] = true
		_y_cache.erase(it)
		items.remove_at(i)
	return gone.size()


## Noktanın yakınında en az bir öğe var mı (fırçayla sık ekerken üst üste binmesin)
func has_near(x: float, z: float, radius: float) -> bool:
	for it in items:
		if (it[1] - x) * (it[1] - x) + (it[2] - z) * (it[2] - z) < radius * radius:
			return true
	return false


static func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


# ---------- Kurulum ----------

func build_all() -> void:
	for k in _chunks:
		(_chunks[k].root as Node).queue_free()
	_chunks.clear()
	_far_queue.clear()
	var by := {}
	for it in items:
		by.get_or_add(_key(it[1], it[2]), []).append(it)
	for k in by:
		_build_chunk(k, by[k])
	_dirty.clear()


func _process(_delta: float) -> void:
	if not _ready_done:
		return
	if not _dirty.is_empty():
		for k in _dirty:
			if _chunks.has(k):
				(_chunks[k].root as Node).queue_free()
				_chunks.erase(k)
			var list := []
			for it in items:
				if _key(it[1], it[2]) == k:
					list.append(it)
			if not list.is_empty():
				_build_chunk(k, list)
		_dirty.clear()
	# Kare başına süre bütçesi: en az bir parsel, bütçe dolunca sonraki kareye
	var start := Time.get_ticks_usec()
	while not _far_queue.is_empty() and Time.get_ticks_usec() - start < FAR_BUDGET_US:
		var k: Vector2i = _far_queue.pop_front()
		if _chunks.has(k) and _chunks[k].far == null:
			var t0 := Time.get_ticks_usec()
			_build_far(k)
			_far_us += Time.get_ticks_usec() - t0
			_far_max_us = maxi(_far_max_us, Time.get_ticks_usec() - t0)


## Uzak meshlerin hepsi kuruldu mu (testler bekler)
func far_pending() -> int:
	return _far_queue.size()


func _on_city_rebuilt() -> void:
	# Şehir zemini düzleştirmiş olabilir: yükseklikler yeniden
	_y_cache.clear()
	if _ready_done:
		build_all()


func _ground_y(it: Array) -> float:
	if _y_cache.has(it):
		return _y_cache[it]
	var x: float = it[1]
	var z: float = it[2]
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -60.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var y: float = hit.position.y if not hit.is_empty() else 0.0
	_y_cache[it] = y
	return y


## Yaprak renk çeşitlemesi: konuma bağlı (her açılışta aynı), parlaklık ve ton hafifçe oynar
static func _tint(x: float, z: float, amount: float) -> Color:
	if amount <= 0.0:
		return Color(1, 1, 1, 1)
	var h1 := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0) - 0.5
	var h2 := fposmod(sin(x * 39.346 + z * 11.135) * 24634.6345, 1.0) - 0.5
	var b := 1.0 + h1 * amount * 2.0
	return Color(b * (1.0 + h2 * amount), b * (1.0 + h2 * amount * 0.3), b * (1.0 - h2 * amount * 0.6), 1.0)


func _xf(it: Array, center: Vector3) -> Transform3D:
	var s: float = it[4]
	var basis := Basis(Vector3.UP, deg_to_rad(it[3])).scaled(Vector3(s, s, s))
	return Transform3D(basis, Vector3(it[1], _ground_y(it), it[2]) - center)


## Yakın modeller ve çarpışma; uzak mesh sıraya girer
func _build_chunk(key: Vector2i, list: Array) -> void:
	var root := Node3D.new()
	root.name = "Peyzaj_%d_%d" % [key.x, key.y]
	var center := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
	root.position = center
	add_child(root)
	var ch := {"root": root, "near": [], "far": null, "list": list, "center": center}
	_chunks[key] = ch
	var by_type := {}
	for it in list:
		by_type.get_or_add(String(it[0]), []).append(it)
	var body: StaticBody3D = null
	for tur in by_type:
		if not _meshes.has(tur):
			continue
		var spec: Dictionary = TURLER[tur]
		var group: Array = by_type[tur]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[tur][0]
		mm.instance_count = group.size()
		for i in group.size():
			var it: Array = group[i]
			var xf := _xf(it, center)
			mm.set_instance_transform(i, xf)
			mm.set_instance_custom_data(i, _tint(it[1], it[2], float(spec.renk)))
			var s: float = it[4]
			var r := float(spec.get("r", 0.0)) * s
			var box: Variant = spec.get("kutu")
			if r <= 0.0 and box == null:
				continue
			if body == null:
				body = StaticBody3D.new()
				body.name = "Govdeler"
				body.collision_layer = Sehir.LAYER
				body.collision_mask = 0
				body.set_meta("surface", "tahta")
				root.add_child(body)
			var cs := CollisionShape3D.new()
			if box != null:
				var bs := BoxShape3D.new()
				bs.size = (box as Vector3) * s
				cs.shape = bs
				cs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(it[3])), xf.origin + Vector3(0, bs.size.y * 0.5, 0))
			else:
				var cyl := CylinderShape3D.new()
				cyl.radius = r
				cyl.height = float(spec.get("h", 3.0)) * s
				cs.shape = cyl
				cs.position = xf.origin + Vector3(0, cyl.height * 0.5, 0)
			body.add_child(cs)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec.golge else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if spec.get("ot", false):
			mi.visibility_range_end = OT_MESAFE
		else:
			# Uzak mesh kurulana dek kendi mesafesiyle; sonra uzak meshe bağlanır
			mi.visibility_range_end = SWITCH + 40.0
			ch.near.append(mi)
		root.add_child(mi)
	_far_queue.append(key)


## Parseldeki her şeyin uzak modelleri tek meshte (yaprak rengi çeşitlemesi köşe rengine işlenir)
func _build_far(key: Vector2i) -> void:
	var ch: Dictionary = _chunks[key]
	var center: Vector3 = ch.center
	var total_v := 0
	var total_i := 0
	for it in ch.list:
		var fa: Variant = _meshes.get(String(it[0]), [null, null])[1]
		if fa != null:
			total_v += (fa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			total_i += (fa[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	if total_v == 0:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(total_v)
	norms.resize(total_v)
	cols.resize(total_v)
	idx.resize(total_i)
	var vo := 0
	var io := 0
	for it in ch.list:
		var fa: Variant = _meshes.get(String(it[0]), [null, null])[1]
		if fa == null:
			continue
		var fv: PackedVector3Array = fa[Mesh.ARRAY_VERTEX]
		var fn: PackedVector3Array = fa[Mesh.ARRAY_NORMAL]
		var fc: PackedColorArray = fa[Mesh.ARRAY_COLOR]
		var fi: PackedInt32Array = fa[Mesh.ARRAY_INDEX]
		var xf := _xf(it, center)
		var b := xf.basis.orthonormalized()
		var t := _tint(it[1], it[2], float(TURLER[it[0]].renk))
		for k in fv.size():
			verts[vo + k] = xf * fv[k]
			norms[vo + k] = b * fn[k]
			var c: Color = fc[k]
			if c.a >= 0.5:
				c = Color(c.r * t.r, c.g * t.g, c.b * t.b, c.a)
			cols[vo + k] = c
		for k in fi.size():
			idx[io + k] = fi[k] + vo
		vo += fv.size()
		io += fi.size()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Uzak"
	mi.mesh = am
	mi.material_override = _mat_far
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mi.visibility_range_begin = SWITCH
	mi.visibility_range_end = UZAK_SON
	(ch.root as Node3D).add_child(mi)
	ch.far = mi
	# Yakınlar artık uzak meshe bağlı: kamera SWITCH'ten yakınken (uzak mesh gizliyken) çizilir
	for n in ch.near:
		var near_mi := n as MultiMeshInstance3D
		near_mi.visibility_range_end = 0.0
		near_mi.visibility_parent = near_mi.get_path_to(mi)
