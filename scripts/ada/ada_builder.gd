class_name AdaBuilder
extends Node3D
## Oyunun geçtiği ada: tools/ada/ada_export.js çıktısından (assets/ada) kurulur.
##   arazi (parça parça, yakın / uzak ayrıntı), deniz, yollar (asfalt şeritleri ve kavşak
##   diskleri), kaldırımlar (bordürlü), orta çizgiler, meydan, çevre bariyeri (harita sınırı,
##   üstü grindlenebilir), iskeleler, başlangıç noktası ve yaya ağı (NPC'ler için).
## Kurulum ağır olduğu için oyunda hazır sahne kullanılır: tools/ada/ada_bake.gd -> scenes/ada.scn
##
## Koordinatlar: plan düzleminde (x doğu, y kuzey, h yükseklik) -> Godot (x, h, -y).

const DATA_PATH := "res://assets/ada/ada.json"
const BIN_PATH := "res://assets/ada/ada_h.bin"
const TOON := preload("res://shaders/toon_char.gdshader")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const COBBLE_SHADER := preload("res://shaders/cobble.gdshader")

## Arazi parçası (m) ve ayrıntı seviyeleri: yakın 4 m ızgara, uzak 16 m
const CHUNK := 128.0
const LOD_NEAR_END := 250.0

const COL_ASPHALT := Color(0.34, 0.33, 0.32)
const COL_DISC := Color(0.35, 0.34, 0.33)
const COL_WALK := Color(0.74, 0.72, 0.68)
const COL_CURB := Color(0.86, 0.85, 0.82)
const COL_LINE := Color(0.95, 0.85, 0.35)
const COL_PLAZA := Color(0.82, 0.74, 0.6)
const COL_BARRIER := Color(0.82, 0.82, 0.8)
const COL_PIER := Color(0.55, 0.4, 0.26)
const COL_SEA := Color(0.24, 0.55, 0.68)
# Zemin türleri (ada_export.js MAT sırası): deniz tabanı, kum, çim, kaya, şev toprağı, yol altı
const TERRAIN_COLORS := [Color(0.62, 0.6, 0.5), Color(0.93, 0.85, 0.62), Color(0.45, 0.66, 0.33),
	Color(0.55, 0.52, 0.47), Color(0.52, 0.42, 0.28), Color(0.4, 0.36, 0.3)]

var data: Dictionary
var _n := 0
var _ext := 0.0
var _step := 2.0
var _h_col := PackedFloat32Array()
var _h_vis := PackedFloat32Array()
var _mat := PackedByteArray()
var _materials := {}


static func p3(x: float, y: float, h: float) -> Vector3:
	return Vector3(x, h, -y)


func build() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var g: Dictionary = data.grid
	_n = int(g.n)
	_ext = float(g.ext)
	_step = float(g.step)
	var bin := FileAccess.get_file_as_bytes(BIN_PATH)
	var nn := _n * _n
	_h_col = bin.slice(0, nn * 4).to_float32_array()
	_h_vis = bin.slice(nn * 4, nn * 8).to_float32_array()
	_mat = bin.slice(nn * 8, nn * 9)

	_build_terrain()
	_build_sea()
	for r in data.roads:
		_build_road(r)
	_build_discs()
	_build_sidewalks()
	_build_center_lines()
	_build_plaza()
	_build_barrier()
	_build_piers()
	_build_street()
	_build_props()

	var sp: Dictionary = data.spawn
	var dir := Vector3(cos(sp.heading), 0, -sin(sp.heading))
	set_meta("spawn", Transform3D(Basis.looking_at(dir, Vector3.UP), p3(sp.x, sp.y, sp.h)))
	var nodes := PackedVector3Array()
	for nd in data.walk.nodes:
		nodes.append(p3(nd[0], nd[1], nd[2]))
	var edges := PackedInt32Array()
	for e in data.walk.edges:
		edges.append(int(e[0]))
		edges.append(int(e[1]))
	set_meta("walk_nodes", nodes)
	set_meta("walk_edges", edges)


# ---------- Malzeme ----------

func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("albedo", color)
		_materials[key] = m
	return _materials[key]


func _mesh_node(mesh: ArrayMesh, color: Color, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _material(color)
	add_child(mi)
	return mi


func _body(node_name: String, surface: String, faces: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.set_meta("surface", surface)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


static func _mesh(verts: PackedVector3Array, idx: PackedInt32Array, colors := PackedColorArray(), uvs := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	# Normaller: üçgen normallerinin köşelerde toplamı (pürüzsüz, toon ışıkla kademeli görünür).
	# Godot'ta ön yüz saat yönünde: normal = (c - a) x (b - a)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var nrm := (c - a).cross(b - a)
		for k in 3:
			normals[idx[t + k]] += nrm
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else Vector3.UP
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## İndeks listesinden çarpışma yüzleri
static func _faces(verts: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var f := PackedVector3Array()
	f.resize(idx.size())
	for i in idx.size():
		f[i] = verts[idx[i]]
	return f


# ---------- Arazi ----------

func _hv(i: int, j: int) -> float:
	return _h_vis[clampi(j, 0, _n - 1) * _n + clampi(i, 0, _n - 1)]


func _build_terrain() -> void:
	var cells := int(CHUNK / _step)            # parça başına ızgara aralığı (2 m örnek)
	var chunks := ceili(float(_n - 1) / cells)
	for cj in chunks:
		for ci in chunks:
			var i0 := ci * cells
			var j0 := cj * cells
			if i0 >= _n - 1 or j0 >= _n - 1:
				continue
			var center := p3(-_ext + (i0 + cells * 0.5) * _step, -_ext + (j0 + cells * 0.5) * _step, 0.0)
			# Tamamen derin denizse atla (deniz düzlemi örter)
			var any_land := false
			for j in range(j0, mini(j0 + cells, _n - 1) + 1, 4):
				for i in range(i0, mini(i0 + cells, _n - 1) + 1, 4):
					if _hv(i, j) > -6.0:
						any_land = true
			if not any_land:
				continue
			var near := _terrain_chunk(i0, j0, cells, 2, center)
			near.name = "Arazi_%d_%d" % [ci, cj]
			near.visibility_range_end = LOD_NEAR_END
			near.visibility_range_end_margin = 20.0
			near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			var far := _terrain_chunk(i0, j0, cells, 8, center)
			far.name = "AraziUzak_%d_%d" % [ci, cj]
			far.visibility_range_begin = LOD_NEAR_END
			far.visibility_range_begin_margin = 20.0
	# Çarpışma: tek yükseklik haritası (2 m), yollar tam yükseklikte gömülü
	var shape := HeightMapShape3D.new()
	shape.map_width = _n
	shape.map_depth = _n
	var hm := PackedFloat32Array()
	hm.resize(_n * _n)
	for r in _n:                                 # Godot satırı: z artar = plan y azalır
		var j := _n - 1 - r
		for i in _n:
			hm[r * _n + i] = _h_col[j * _n + i]
	shape.map_data = hm
	var body := StaticBody3D.new()
	body.name = "AraziCarpisma"
	body.set_meta("surface", "cim")
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(_step, 1.0, _step)
	body.add_child(cs)
	add_child(body)


## Bir arazi parçası; stride: kaç örnekte bir köşe (2 -> 4 m, 8 -> 16 m)
func _terrain_chunk(i0: int, j0: int, cells: int, stride: int, center: Vector3) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var i1 := mini(i0 + cells, _n - 1)
	var j1 := mini(j0 + cells, _n - 1)
	var cols := 0
	var rows := 0
	var j := j0
	while true:
		rows += 1
		cols = 0
		var i := i0
		while true:
			cols += 1
			var x := -_ext + i * _step
			var y := -_ext + j * _step
			verts.append(p3(x, y, _hv(i, j)) - center)
			var m := int(_mat[j * _n + i])
			var c: Color = TERRAIN_COLORS[clampi(m, 0, TERRAIN_COLORS.size() - 1)]
			# Hafif renk oynaması: düz renkler canlı dursun
			var hsh := fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			c = c.lightened((hsh - 0.5) * 0.08) if hsh > 0.5 else c.darkened((0.5 - hsh) * 0.08)
			colors.append(c.srgb_to_linear())
			if i >= i1:
				break
			i = mini(i + stride, i1)
		if j >= j1:
			break
		j = mini(j + stride, j1)
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			# Plan y yukarı = Godot -z: üçgen sırası yukarı bakan normal verecek şekilde
			idx.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
	_fix_winding(verts, idx)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(verts, idx, colors)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi


func _build_sea() -> void:
	var size := _ext * 2.0 + 1600.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := 40
	for j in n + 1:
		for i in n + 1:
			verts.append(Vector3(-size * 0.5 + size * i / n, 0.0, -size * 0.5 + size * j / n))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	_fix_winding(verts, idx)
	_mesh_node(_mesh(verts, idx), COL_SEA, "Deniz")


# ---------- Yollar ----------

## Çizgi boyunca şerit: her noktada sol / sağ kenar (merkezden off1..off2 uzaklıkta)
static func _strip(pts: Array, off1: float, off2: float, lift: float, closed: bool, verts: PackedVector3Array, idx: PackedInt32Array,
		h1 := [], h2 := []) -> void:
	var n := pts.size()
	var base := verts.size()
	for i in n:
		var a: Array = pts[maxi(i - 1, 0)] if not closed or i > 0 else pts[n - 2]
		var b: Array = pts[mini(i + 1, n - 1)] if not closed or i < n - 1 else pts[1]
		var d := Vector2(b[0] - a[0], b[1] - a[1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		var p: Array = pts[i]
		var h: float = p[2] + lift
		# Kenar yükseklikleri verilmişse (kavşakta yol yüzeyi) onlar
		var ha: float = (float(h1[i]) + lift) if h1.size() == n else h
		var hb: float = (float(h2[i]) + lift) if h2.size() == n else h
		verts.append(p3(p[0] + nrm.x * off1, p[1] + nrm.y * off1, ha))
		verts.append(p3(p[0] + nrm.x * off2, p[1] + nrm.y * off2, hb))
	for i in n - 1:
		var k := base + i * 2
		idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])


func _build_road(r: Dictionary) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var w: float = r.width
	var rib: Array = r.get("rib", [])
	if rib.size() >= 2:
		# Satırlar: sol, orta, sağ köşe (yol yüzeyinde); iki şerit üçgen
		for row in rib:
			for k in 3:
				verts.append(p3(row[k * 3], row[k * 3 + 1], row[k * 3 + 2] + 0.02))
		for i in rib.size() - 1:
			var a := i * 3
			var b := a + 3
			idx.append_array([a, b, a + 1, a + 1, b, b + 1, a + 1, b + 1, a + 2, a + 2, b + 1, b + 2])
	else:
		_strip(r.pts, -w * 0.5, w * 0.5, 0.02, r.closed, verts, idx)
	_fix_winding(verts, idx)
	_mesh_node(_mesh(verts, idx), COL_ASPHALT, "Yol_" + str(r.id))
	_body("YolCarpisma_" + str(r.id), "asfalt", _faces(verts, idx))


## Üçgenler yukarı baksın (Godot'ta ön yüz saat yönünde; şerit yönüne göre sıra ters olabilir)
static func _fix_winding(verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var nrm := (verts[idx[t + 2]] - a).cross(verts[idx[t + 1]] - a)
		if nrm.y < 0.0:
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp


func _disc_mesh(cx: float, cy: float, h: float, radius: float, seg: int, verts: PackedVector3Array, idx: PackedInt32Array, rim := []) -> void:
	var c := verts.size()
	verts.append(p3(cx, cy, h))
	for k in seg:
		var a := TAU * k / seg
		var hk: float = float(rim[k]) + 0.025 if rim.size() == seg else h
		verts.append(p3(cx + cos(a) * radius, cy + sin(a) * radius, hk))
	for k in seg:
		idx.append_array([c, c + 1 + (k + 1) % seg, c + 1 + k])


func _build_discs() -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var pv: Dictionary = data.get("paved", {})
	if not pv.is_empty():
		# Kavşak kaplaması: yol yüzeyine oturan sık ızgara (ada_export.js "paved")
		for v in pv.v:
			verts.append(p3(v[0], v[1], v[2] + 0.025))
		for i in pv.t:
			idx.append(int(i))
	else:
		for d in data.discs:
			if d.plaza:
				continue
			_disc_mesh(d.x, d.y, d.h + 0.025, d.r, 20, verts, idx, d.get("rim", []))
		for f in data.get("cornerFills", []):
			var c := verts.size()
			verts.append(p3(f.c[0], f.c[1], f.c[2] + 0.024))
			for q in f.pts:
				verts.append(p3(q[0], q[1], q[2] + 0.022))
			for k in f.pts.size() - 1:
				idx.append_array([c, c + 1 + k, c + 2 + k])
	_fix_winding(verts, idx)
	_mesh_node(_mesh(verts, idx), COL_DISC, "Kavsaklar")
	_body("KavsakCarpisma", "asfalt", _faces(verts, idx))


func _build_sidewalks() -> void:
	var curb: float = data.curb
	var top := PackedVector3Array()
	var top_idx := PackedInt32Array()
	var face := PackedVector3Array()
	var face_idx := PackedInt32Array()
	for run in data.sidewalks:
		var pts: Array = run.pts
		# Üst yüzey: iç kenardan dış kenara, bordür yüksekliğinde
		var b := top.size()
		for p in pts:
			top.append(p3(p[0], p[1], p[4] + curb))
			top.append(p3(p[2], p[3], p[4] + curb))
		for i in pts.size() - 1:
			var k := b + i * 2
			top_idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
		# Bordür yüzü (yola bakar) ve dış yüz (araziye iner, dışa bakar); tek yüzlü:
		# iki yüzlü üçgenlerin normalleri birbirini sıfırlıyor, yüzey titriyordu
		for edge in [[0, 1, 0.02, 2, 3], [2, 3, -1.2, 0, 1]]:
			for i in pts.size() - 1:
				var p: Array = pts[i]
				var q: Array = pts[i + 1]
				var top0 := p3(p[edge[0]], p[edge[1]], p[4] + curb)
				var top1 := p3(q[edge[0]], q[edge[1]], q[4] + curb)
				if top0.distance_squared_to(top1) < 0.0001:
					continue
				var inside := (p3(p[edge[3]], p[edge[4]], p[4]) + p3(q[edge[3]], q[edge[4]], q[4])) * 0.5
				_quad_out(top0, top1, p3(q[edge[0]], q[edge[1]], q[4] + edge[2]), p3(p[edge[0]], p[edge[1]], p[4] + edge[2]), inside, face, face_idx)
		# Uç kapakları: kaldırım bir yerde bitiyorsa altı açık görünmesin (kapalı halkada yok)
		var f0: Array = pts[0]
		var f1: Array = pts[pts.size() - 1]
		if Vector2(f0[0] - f1[0], f0[1] - f1[1]).length() > 0.05:
			for e in [[0, 1], [pts.size() - 1, pts.size() - 2]]:
				var c: Array = pts[e[0]]
				var o: Array = pts[e[1]]
				var inside := p3((o[0] + o[2]) * 0.5, (o[1] + o[3]) * 0.5, o[4])
				_quad_out(p3(c[0], c[1], c[4] + curb), p3(c[2], c[3], c[4] + curb), p3(c[2], c[3], c[4] - 1.2), p3(c[0], c[1], c[4] - 1.2), inside, face, face_idx)
	_fix_winding(top, top_idx)
	_mesh_node(_mesh(top, top_idx), COL_WALK, "Kaldirimlar")
	_mesh_node(_mesh(face, face_idx), COL_CURB, "Bordurler")
	var all := _faces(top, top_idx)
	all.append_array(_faces(face, face_idx))
	_body("KaldirimCarpisma", "beton", all)


func _build_center_lines() -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	const DASH := 3.0
	const GAP := 4.0
	const HALF := 0.08
	for run in data.centerLines:
		var acc := 0.0
		for i in run.size() - 1:
			var a: Array = run[i]
			var b: Array = run[i + 1]
			var L := Vector2(b[0] - a[0], b[1] - a[1]).length()
			if L < 0.01:
				continue
			var d := Vector2(b[0] - a[0], b[1] - a[1]) / L
			var nrm := Vector2(-d.y, d.x) * HALF
			var s := 0.0
			while s < L:
				var phase := fmod(acc + s, DASH + GAP)
				var seg_end := minf(L, s + (DASH - phase if phase < DASH else DASH + GAP - phase))
				if phase < DASH:
					var t0 := s / L
					var t1 := seg_end / L
					var p0 := Vector3(lerpf(a[0], b[0], t0), lerpf(a[1], b[1], t0), lerpf(a[2], b[2], t0) + 0.035)
					var p1 := Vector3(lerpf(a[0], b[0], t1), lerpf(a[1], b[1], t1), lerpf(a[2], b[2], t1) + 0.035)
					var k := verts.size()
					verts.append(p3(p0.x + nrm.x, p0.y + nrm.y, p0.z))
					verts.append(p3(p0.x - nrm.x, p0.y - nrm.y, p0.z))
					verts.append(p3(p1.x + nrm.x, p1.y + nrm.y, p1.z))
					verts.append(p3(p1.x - nrm.x, p1.y - nrm.y, p1.z))
					idx.append_array([k, k + 2, k + 1, k + 1, k + 2, k + 3])
				s = seg_end + 0.0001
			acc += L
	_fix_winding(verts, idx)
	_mesh_node(_mesh(verts, idx), COL_LINE, "OrtaCizgiler")


func _build_plaza() -> void:
	var p: Dictionary = data.plaza
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	_disc_mesh(p.x, p.y, p.h + 0.03, p.r, 40, verts, idx)
	_fix_winding(verts, idx)
	# Arnavut kaldırımı (test pistindeki taş deseni, dünya koordinatında)
	var mi := MeshInstance3D.new()
	mi.name = "Meydan"
	mi.mesh = _mesh(verts, idx)
	var mat := ShaderMaterial.new()
	mat.shader = COBBLE_SHADER
	mi.material_override = mat
	add_child(mi)
	_body("MeydanCarpisma", "arnavut", _faces(verts, idx))


# ---------- Çevre bariyeri ----------

## Beton (New Jersey) bariyer: taban 0,6 m, üst 0,22 m, yükseklik 0,55 m; deniz tarafındaki
## kaldırımın dış kenarına oturur. Üstü grindlenir: kısa, uç uca eklenmiş raylar eğriyi izler
## (kontrolcü bir sonrakine kesintisiz geçer). Arkasında görünmez yüksek duvar: bariyerin
## üstünden atlanıp haritadan çıkılamaz.
## Her yüz kendi köşeleriyle (keskin kenarlı, ışık yüze göre), dışa bakacak sırayla.
func _build_barrier() -> void:
	const H := 0.55
	const PROFILE := [[-0.3, 0.0], [-0.17, 0.18], [-0.11, 0.55], [0.11, 0.55], [0.17, 0.18], [0.3, 0.0]]
	const RAIL_STEP := 5.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for run in data.barrier:
		var n: int = run.size()
		var rings: Array = []          # her noktada profil köşeleri
		var axis: Array = []           # profilin orta noktası (yüz yönü için)
		var nrms: Array = []
		for i in n:
			var p: Array = run[i]
			var a: Array = run[maxi(i - 1, 0)]
			var b: Array = run[mini(i + 1, n - 1)]
			var d := Vector2(b[0] - a[0], b[1] - a[1]).normalized()
			var nrm := Vector2(-d.y, d.x)
			var ring := []
			for q in PROFILE:
				ring.append(p3(p[0] + nrm.x * q[0], p[1] + nrm.y * q[0], p[2] + q[1]))
			rings.append(ring)
			axis.append(p3(p[0], p[1], p[2] + 0.2))
			nrms.append(nrm)
		var m := PROFILE.size()
		for i in n - 1:
			var mid: Vector3 = (axis[i] + axis[i + 1]) * 0.5
			for k in m - 1:
				_quad_out(rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k + 1], mid, verts, idx)
		# Uç kapakları (liman ağzında)
		for e in [[0, 1], [n - 1, n - 2]]:
			var ring: Array = rings[e[0]]
			var out: Vector3 = axis[e[0]] + (axis[e[0]] - axis[e[1]]).normalized()
			var base := verts.size()
			for v in ring:
				verts.append(v)
			for k in range(1, m - 1):
				var t := [base, base + k, base + k + 1]
				var nn := (verts[t[2]] - verts[t[0]]).cross(verts[t[1]] - verts[t[0]])
				if nn.dot(out - verts[t[0]]) < 0.0:
					t = [t[0], t[2], t[1]]
				idx.append_array(t)
		# Görünmez duvar: bariyerin deniz tarafı kenarında, 3,5 m
		var wall := []
		for i in n:
			var p: Array = run[i]
			var nrm: Vector2 = nrms[i]
			if nrm.dot(Vector2(p[0], p[1])) < 0.0:
				nrm = -nrm
			var wb := p3(p[0] + nrm.x * 0.32, p[1] + nrm.y * 0.32, p[2])
			wall.append([wb, wb + Vector3(0, 3.5, 0)])
		for i in n - 1:
			faces.append_array([wall[i][0], wall[i + 1][0], wall[i][1], wall[i][1], wall[i + 1][0], wall[i + 1][1]])
		# Grind rayları: üst ortası, ~5 m'lik parçalar uç uca
		var seg_start := p3(run[0][0], run[0][1], run[0][2] + H)
		var acc := 0.0
		for i in range(1, n):
			var top := p3(run[i][0], run[i][1], run[i][2] + H)
			var prev := p3(run[i - 1][0], run[i - 1][1], run[i - 1][2] + H)
			acc += top.distance_to(prev)
			if acc >= RAIL_STEP or i == n - 1:
				var rail := GrindRail.new()
				add_child(rail)
				rail.setup(seg_start, top, "beton")
				seg_start = top
				acc = 0.0
	_mesh_node(_mesh(verts, idx), COL_BARRIER, "Bariyer")
	faces.append_array(_faces(verts, idx))
	_body("BariyerCarpisma", "beton", faces)


## Dörtgen, kendi köşeleriyle; ön yüzü "inside" noktasından uzağa bakar
static func _quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var k := verts.size()
	verts.append_array([a, b, c, d])
	var t := [k, k + 1, k + 2, k, k + 2, k + 3]
	var nn := (c - a).cross(b - a)
	if nn.dot((a + b + c + d) * 0.25 - inside) < 0.0:
		t = [k, k + 2, k + 1, k, k + 3, k + 2]
	idx.append_array(t)


func _build_piers() -> void:
	for i in data.piers.size():
		var p: Dictionary = data.piers[i]
		var body := StaticBody3D.new()
		body.name = "Iskele_%d" % i
		body.set_meta("surface", "tahta")
		var size := Vector3(p.length, 1.2, p.width)
		var mesh := BoxMesh.new()
		mesh.size = size
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material(COL_PIER)
		body.add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		body.position = p3(p.x, p.y, p.h - 0.6)
		body.rotation.y = p.angle
		add_child(body)
		# Direkler
		for k in 6:
			for s in [-1, 1]:
				var post := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.35, 3.0, 0.35)
				post.mesh = pm
				post.material_override = _material(COL_PIER.darkened(0.25))
				post.position = Vector3(-p.length * 0.5 + (k + 0.5) * p.length / 6.0, -1.6, s * (p.width * 0.5 - 0.3))
				body.add_child(post)


# ---------- Sokak düzeni: yaya geçitleri, dur çizgileri, trafik ışıkları, tabelalar, reklam panoları ----------

const TABELA_SHADER := preload("res://shaders/tabela.gdshader")
const LAMBA_SHADER := preload("res://shaders/trafik_lamba.gdshader")
const DIREK_SHADER := preload("res://shaders/direk.gdshader")
const ISIK_SCRIPT := preload("res://scripts/traffic/trafik_isiklari.gd")
const COL_PAINT := Color(0.93, 0.93, 0.9)
const COL_POLE := Color(0.32, 0.33, 0.35)
const COL_BOARD := Color(0.2, 0.2, 0.22)


## Arazi (çarpışma) yüksekliği: plan noktasında ızgaradan çift doğrusal
func _ground(x: float, y: float) -> float:
	var fi := (x + _ext) / _step
	var fj := (y + _ext) / _step
	var i := clampi(int(fi), 0, _n - 2)
	var j := clampi(int(fj), 0, _n - 2)
	var u := clampf(fi - i, 0.0, 1.0)
	var v := clampf(fj - j, 0.0, 1.0)
	var a := lerpf(_h_col[j * _n + i], _h_col[j * _n + i + 1], u)
	var b := lerpf(_h_col[(j + 1) * _n + i], _h_col[(j + 1) * _n + i + 1], u)
	return lerpf(a, b, v)


## Plan düzleminde (x, y) yönden Godot yatay yön
static func _gdir(fx: float, fy: float) -> Vector3:
	return Vector3(fx, 0.0, -fy).normalized()


## Yere paralel dikdörtgen (boya): merkez, uzun eksen yönü, yarı boy ve yarı en
static func _flat_quad(c: Vector3, along: Vector3, half_l: float, half_w: float, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var side := along.cross(Vector3.UP).normalized()
	var k := verts.size()
	verts.append_array([c - along * half_l - side * half_w, c + along * half_l - side * half_w,
		c + along * half_l + side * half_w, c - along * half_l + side * half_w])
	idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])


## Kutu (direk, pano çerçevesi): taban merkezi, sağ yön, boyut (en, yükseklik, derinlik)
static func _box(base: Vector3, right: Vector3, size: Vector3, verts: PackedVector3Array, idx: PackedInt32Array) -> void:
	var r := right.normalized() * size.x * 0.5
	var f := right.cross(Vector3.UP).normalized() * size.z * 0.5
	var u := Vector3.UP * size.y
	var c := [base - r - f, base + r - f, base + r + f, base - r + f]
	var mid := base + u * 0.5
	for k in 4:
		var a: Vector3 = c[k]
		var b: Vector3 = c[(k + 1) % 4]
		_quad_out(a, b, b + u, a + u, mid, verts, idx)
	_quad_out(c[0] + u, c[1] + u, c[2] + u, c[3] + u, mid, verts, idx)


## Direk: kutu + her köşede eksenden yatay uzaklık (UV); direk shader'ı uzakta en az ~1 piksel tutar
static func _pole(base: Vector3, right: Vector3, size: Vector3, verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array) -> void:
	var k := verts.size()
	_box(base, right, size, verts, idx)
	for i in range(k, verts.size()):
		uvs.append(Vector2(verts[i].x - base.x, verts[i].z - base.z))


func _pole_node(verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _mesh(verts, idx, PackedColorArray(), uvs)
	var mat := ShaderMaterial.new()
	mat.shader = DIREK_SHADER
	mat.set_shader_parameter("albedo", COL_POLE)
	mi.material_override = mat
	add_child(mi)
	return mi


func _build_street() -> void:
	var st: Dictionary = data.get("street", {})
	if st.is_empty():
		return
	_build_road_paint(st)
	_build_lights(st)
	_build_signs(st)
	var cross := PackedInt32Array()
	for c in data.walk.get("cross", []):
		cross.append_array([int(c[0]), int(c[1]), int(c[2]), int(c[3])])
	set_meta("walk_cross", cross)


## Yaya geçidi zebraları (trafik yönüne paralel şeritler) ve dur çizgileri
func _build_road_paint(st: Dictionary) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var paint: Array = st.get("paint", [])
	for k in range(0, paint.size() - 3, 4):
		var b := verts.size()
		for q in 4:
			var v: Array = paint[k + q]
			verts.append(p3(v[0], v[1], v[2]))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	_fix_winding(verts, idx)
	var mi := _mesh_node(_mesh(verts, idx), COL_PAINT, "YolBoyalari")


## Işık direkleri (tek mesh + çarpışma) ve başlar (MultiMesh, durumları trafik_isiklari.gd)
func _build_lights(st: Dictionary) -> void:
	var pv := PackedVector3Array()
	var pi := PackedInt32Array()
	var puv := PackedVector2Array()
	var car_tf: Array[Transform3D] = []
	var ped_tf: Array[Transform3D] = []
	var car_j := PackedInt32Array()
	var car_a := PackedInt32Array()
	var ped_j := PackedInt32Array()
	var ped_a := PackedInt32Array()
	for L in st.lights:
		var base := p3(L.p[0], L.p[1], L.p[2] - 0.05)
		var face := _gdir(L.f[0], L.f[1])
		var car: bool = L.kind == "arac"
		var head_h := 2.55 if car else 2.05
		_pole(base, face.cross(Vector3.UP), Vector3(0.11, head_h + (0.45 if car else 0.32), 0.11), pv, pi, puv)
		var tf := Transform3D(Basis.looking_at(-face, Vector3.UP), base + Vector3.UP * head_h + face * 0.12)
		if car:
			car_tf.append(tf)
			car_j.append(int(L.j))
			car_a.append(int(L.arm))
		else:
			ped_tf.append(tf)
			ped_j.append(int(L.j))
			ped_a.append(int(L.arm))
	var poles := _pole_node(pv, pi, puv, "IsikDirekleri")
	_body("IsikDirekCarpisma", "metal", _faces(pv, pi))
	_lamp_multimesh("AracIsiklari", car_tf, car_j, car_a, 0)
	_lamp_multimesh("YayaIsiklari", ped_tf, ped_j, ped_a, 1)


func _lamp_multimesh(node_name: String, tfs: Array[Transform3D], js: PackedInt32Array, arms: PackedInt32Array, kind: int) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mat := ShaderMaterial.new()
	mat.shader = LAMBA_SHADER
	mmi.material_override = mat
	mmi.set_script(ISIK_SCRIPT)
	var pos := PackedVector3Array()
	var fc := PackedVector3Array()
	for tf in tfs:
		pos.append(tf.origin)
		fc.append(tf.basis.z)
	mmi.set("junction", js)
	mmi.set("arm", arms)
	mmi.set("positions", pos)
	mmi.set("faces", fc)
	mmi.set("car_heads", kind == 0)
	var kinds := PackedInt32Array()
	kinds.resize(tfs.size())
	kinds.fill(kind)
	mmi.set("kind", kinds)
	add_child(mmi)


## Işık başı: gövde kutusu ve ön yüzde (+Z) lambalar; lamba kimliği köşe renginde
static func _lamp_head(car: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var cols := PackedColorArray()
	var size := Vector3(0.3, 0.86, 0.22) if car else Vector3(0.3, 0.58, 0.2)
	_box(Vector3(0, -size.y * 0.5, -size.z * 0.5), Vector3.RIGHT, size, verts, idx)
	cols.resize(verts.size())
	cols.fill(Color(0, 0, 0))
	var lamps := [[1, 0.27], [2, 0.0], [3, -0.27]] if car else [[1, 0.13], [3, -0.13]]
	var r := 0.1 if car else 0.11
	for lamp in lamps:
		var lc := Color(lamp[0] / 4.0, 0, 0)
		var c := Vector3(0, lamp[1], 0.012)
		var k := verts.size()
		verts.append(c)
		cols.append(lc)
		var seg := 8
		for s in seg:
			var a := TAU * s / seg
			verts.append(c + Vector3(cos(a) * r, sin(a) * r, 0))
			cols.append(lc)
		for s in seg:
			idx.append_array([k, k + 1 + s, k + 1 + (s + 1) % seg])
		# Siperlik: lambanın üstünde ileri uzanan küçük çatı (gövde rengi, iki yüzlü)
		var vb := verts.size()
		var vy: float = lamp[1] + r + 0.02
		verts.append_array([Vector3(-r - 0.02, vy, 0.0), Vector3(r + 0.02, vy, 0.0), Vector3(r + 0.02, vy - 0.03, 0.12), Vector3(-r - 0.02, vy - 0.03, 0.12)])
		cols.append_array([Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)])
		idx.append_array([vb, vb + 2, vb + 1, vb, vb + 3, vb + 2, vb, vb + 1, vb + 2, vb, vb + 2, vb + 3])
	# Lamba diskleri +Z'ye baksın (Godot ön yüzü: normal = (c - a) x (b - a))
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var nrm := (verts[idx[t + 2]] - a).cross(verts[idx[t + 1]] - a)
		if cols[idx[t]].r > 0.0 and nrm.z < 0.0:
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	return _mesh(verts, idx, cols)


## Tabelalar (levha, yön, sokak adı) ve reklam panoları: levhalar tek mesh (tek doku),
## direkler ve pano iskeletleri tek mesh + çarpışma.
func _build_signs(st: Dictionary) -> void:
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ada/tabelalar.json"))
	var sv := PackedVector3Array()
	var suv := PackedVector2Array()
	var si := PackedInt32Array()
	var pv := PackedVector3Array()
	var pi := PackedInt32Array()
	var puv := PackedVector2Array()
	var bv := PackedVector3Array()
	var bi := PackedInt32Array()
	var back: Array = atlas.arka

	for s in st.signs:
		if not atlas.has(s.key):
			continue
		var cell: Array = atlas[s.key]
		var base := p3(s.p[0], s.p[1], s.p[2] - 0.05)
		var face := _gdir(s.f[0], s.f[1])
		var right := Vector3.UP.cross(face).normalized()
		match s.kind:
			"levha":
				_plate(base + Vector3.UP * 2.25, face, 0.72, 0.72, cell, back, sv, suv, si)
				_pole(base - face * 0.05, right, Vector3(0.07, 2.62, 0.07), pv, pi, puv)
			"yon":
				var w := 1.9
				var h: float = w / float(cell[4])
				_plate(base + Vector3.UP * (2.1 + h * 0.5), face, w, h, cell, back, sv, suv, si)
				for sx in [-0.7, 0.7]:
					_pole(base + right * sx - face * 0.05, right, Vector3(0.08, 2.1 + h, 0.08), pv, pi, puv)
			"ad":
				var w := 1.2
				var h: float = w / float(cell[4])
				_plate(base + Vector3.UP * 2.7, face, w, h, cell, cell, sv, suv, si)
				_pole(base - right * (w * 0.5 + 0.05), right, Vector3(0.07, 2.7 + h * 0.5, 0.07), pv, pi, puv)

	# Reklam panoları: 6,4 x 3,2 m levha, iki ayak, arka çerçeve; zemine oturur
	var designs := 0
	for k in atlas:
		if String(k).begins_with("reklam_"):
			designs += 1
	for b in st.billboards:
		var key := "reklam_%d" % (int(b.idx) % maxi(designs, 1))
		if not atlas.has(key):
			continue
		var gy := minf(_ground(b.p[0], b.p[1]), float(b.p[2]) + 2.0)
		var base := p3(b.p[0], b.p[1], gy - 0.3)
		var face := _gdir(b.f[0], b.f[1])
		var right := Vector3.UP.cross(face).normalized()
		var W := 6.4
		var H := 3.2
		_plate(base + Vector3.UP * (3.3 + H * 0.5) + face * 0.09, face, W, H, atlas[key], back, sv, suv, si)
		_box(base + Vector3.UP * 3.15, right, Vector3(W + 0.3, H + 0.3, 0.16), bv, bi)
		for sx in [-W * 0.3, W * 0.3]:
			_box(base + right * sx - face * 0.25, right, Vector3(0.28, 3.3, 0.28), bv, bi)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sv
	arrays[Mesh.ARRAY_TEX_UV] = suv
	arrays[Mesh.ARRAY_INDEX] = si
	var normals := PackedVector3Array()
	normals.resize(sv.size())
	for t in range(0, si.size(), 3):
		var nrm := (sv[si[t + 2]] - sv[si[t]]).cross(sv[si[t + 1]] - sv[si[t]]).normalized()
		for q in 3:
			normals[si[t + q]] = nrm
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Tabelalar"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = TABELA_SHADER
	mat.set_shader_parameter("atlas", load("res://assets/ada/tabelalar.png"))
	mi.material_override = mat
	add_child(mi)

	var poles := _pole_node(pv, pi, puv, "TabelaDirekleri")
	var boards := _mesh_node(_mesh(bv, bi), COL_BOARD, "PanoIskeletleri")
	var all := _faces(pv, pi)
	all.append_array(_faces(bv, bi))
	_body("TabelaCarpisma", "metal", all)


## İki yüzlü levha: önde hücre, arkada arka hücre (sokak adında aynı yazı, ters çevrilmeden okunur)
static func _plate(center: Vector3, face: Vector3, w: float, h: float, cell: Array, back_cell: Array,
		sv: PackedVector3Array, suv: PackedVector2Array, si: PackedInt32Array) -> void:
	var right := Vector3.UP.cross(face).normalized()
	for side in [1, -1]:
		var c: Vector3 = center + face * 0.012 * side
		var cl: Array = cell if side == 1 else back_cell
		var u0: float = cl[0]
		var u1: float = cl[2]
		# Arkadan bakınca sağ yön tersine döner: aynı yazının okunması için U da ters verilir
		var rr: Vector3 = right * side
		var k := sv.size()
		sv.append_array([c - rr * w * 0.5 - Vector3.UP * h * 0.5, c + rr * w * 0.5 - Vector3.UP * h * 0.5,
			c + rr * w * 0.5 + Vector3.UP * h * 0.5, c - rr * w * 0.5 + Vector3.UP * h * 0.5])
		suv.append_array([Vector2(u0, cl[3]), Vector2(u1, cl[3]), Vector2(u1, cl[1]), Vector2(u0, cl[1])])
		var nrm := (sv[k + 2] - sv[k]).cross(sv[k + 1] - sv[k])
		if nrm.dot(face * side) >= 0.0:
			si.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
		else:
			si.append_array([k, k + 2, k + 1, k, k + 3, k + 2])


# ---------- Sokak eşyaları (Poly Haven, assets/props): tür ve 128 m bölge başına bir MultiMesh ----------

const PROP_SCRIPT := preload("res://scripts/ada/prop_katmani.gd")
## Tür: [çarpışma ("silindir" yarıçap, boy) ya da ("kutu" en, boy, derinlik), görünürlük mesafesi]
const PROPS := {
	"street_lamp_01": [["silindir", 0.13, 3.8], 300.0],
	"painted_wooden_bench": [["kutu", 1.16, 0.89, 0.5], 170.0],
	"metal_trash_can": [["silindir", 0.3, 0.9], 150.0],
	"fire_hydrant": [["silindir", 0.15, 0.8], 140.0],
	"planter_box_01": [["kutu", 0.93, 0.43, 0.43], 150.0],
	"barrel_03": [["silindir", 0.32, 0.93], 170.0],
	"plastic_crate_02": [["kutu", 0.51, 0.25, 0.4], 140.0],
}


func _build_props() -> void:
	var list: Array = data.get("street", {}).get("props", [])
	var groups := {}
	for q in list:
		if not PROPS.has(q.t):
			continue
		var pos := p3(q.p[0], q.p[1], q.p[2] - 0.02)
		var key := "%s|%d|%d" % [q.t, floori(pos.x / CHUNK), floori(pos.z / CHUNK)]
		if not groups.has(key):
			groups[key] = {"t": q.t, "items": []}
		var dir := _gdir(q.f[0], q.f[1])
		groups[key].items.append(Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
	for key in groups:
		var g: Dictionary = groups[key]
		var items: Array = g.items
		var center := Vector3.ZERO
		for tf in items:
			center += tf.origin
		center /= items.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Esya_" + String(key).replace("|", "_")
		mmi.position = center
		mmi.set_script(PROP_SCRIPT)
		mmi.set("model_path", "res://assets/props/%s.glb" % g.t)
		var rel: Array[Transform3D] = []
		for tf in items:
			rel.append(Transform3D(tf.basis, tf.origin - center))
		mmi.set("transforms", rel)
		mmi.visibility_range_end = PROPS[g.t][1]
		add_child(mmi)
		# Çarpışma: basit şekiller (kaykayla çarpılır, üstüne çıkılabilir)
		var body := StaticBody3D.new()
		body.name = "EsyaCarpisma_" + String(key).replace("|", "_")
		body.set_meta("surface", "metal")
		var spec: Array = PROPS[g.t][0]
		for tf in items:
			var cs := CollisionShape3D.new()
			if spec[0] == "silindir":
				var sh := CylinderShape3D.new()
				sh.radius = spec[1]
				sh.height = spec[2]
				cs.shape = sh
				cs.transform = Transform3D(tf.basis, tf.origin + Vector3.UP * spec[2] * 0.5)
			else:
				var sh := BoxShape3D.new()
				sh.size = Vector3(spec[1], spec[2], spec[3])
				cs.shape = sh
				cs.transform = Transform3D(tf.basis, tf.origin + Vector3.UP * spec[2] * 0.5)
			body.add_child(cs)
		add_child(body)
