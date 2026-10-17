class_name CanliOdalar
extends Node3D
## Oyuncuya yakın binaların zemin katında gerçek 3D odalar: duvarlar, mobilya ve çalışan
## hayvanlar (sokaktaki NPC modelleri). Uzaktaki pencerelerde oda gölgelendiriciyle sahte çizilir
## (shaders/bina.gdshader); burada açılan odaların camı gölgelendiricide delinir (cut_a / cut_b),
## arkasındaki gerçek oda görünür. En çok MAX_ROOMS oda; yakınlık değiştikçe yeniden kurulur.
##
## Yuvalar şehir kurulurken Sehir.room_slots'a yazılır (ön cephe, zemin kat).

const MAX_ROOMS := 4
const NEAR := 18.0
const ROOM_H := 2.85
const ROOM_D := 3.0
const TICK := 0.3
const ROOM_DIM := 0.62

var city: Sehir
var _active := {}            # yuva kimliği -> {node, slot}
var _t := 0.0
var _mats := {}
var _vc_mat: ShaderMaterial


func _ready() -> void:
	_vc_mat = ShaderMaterial.new()
	_vc_mat.shader = Sehir.VC_SHADER


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or city == null:
		return
	_t = TICK
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	# En yakın yuvalar (yalnız sokaktan: cephenin önündeysek)
	var cands: Array = []
	for slot in city.room_slots:
		var c: Vector3 = slot.center
		var dd := Vector2(p.x - c.x, p.z - c.z).length()
		if dd > NEAR:
			continue
		var n: Vector3 = slot.normal
		if (p - c).dot(n) < 0.5:
			continue
		cands.append([dd, slot])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var want := {}
	for i in mini(cands.size(), MAX_ROOMS):
		want[int(cands[i][1].id)] = cands[i][1]
	var changed := false
	for id in _active.keys():
		if not want.has(id):
			(_active[id].node as Node).queue_free()
			_active.erase(id)
			changed = true
	# Bir tikte en çok bir oda kurulur (takılma olmasın)
	for id in want:
		if not _active.has(id):
			_active[id] = {"node": _build_room(want[id]), "slot": want[id]}
			changed = true
			break
	if changed:
		_update_cuts()


## Gölgelendiriciye açık odaların camını bildir
func _update_cuts() -> void:
	var a: Array[Vector4] = []
	var b: Array[Vector4] = []
	for id in _active:
		var s: Dictionary = _active[id].slot
		var c: Vector3 = s.center
		var n: Vector3 = s.normal
		a.append(Vector4(c.x, c.z, n.x, n.z))
		b.append(Vector4(float(s.width) * 0.5 - 0.1, c.y - 0.5, c.y + KAT_TOP, 1.0))
	while a.size() < MAX_ROOMS:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
	var m := city.bina_material()
	m.set_shader_parameter("cut_a", a)
	m.set_shader_parameter("cut_b", b)


const KAT_TOP := 2.95


func _clear() -> void:
	for id in _active:
		(_active[id].node as Node).queue_free()
	_active.clear()
	_update_cuts()


## Bir oda: cephenin arkasında içe bakan kutu, mobilya, ışık ve hayvanlar
func _build_room(slot: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(slot.seed * 7919.0) + 13
	var root := Node3D.new()
	add_child(root)
	var n: Vector3 = slot.normal
	var right: Vector3 = Vector3.UP.cross(n).normalized()
	root.global_transform = Transform3D(Basis(right, Vector3.UP, n), slot.center)
	var w := float(slot.width) - 0.3
	var d := minf(float(slot.depth) - 0.4, ROOM_D)
	var shop := bool(slot.shop)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := ["#f3e6cf", "#dfe9e3", "#e9dcef", "#f6e0d2", "#e0e6f2", "#f2efe0"]
	var wall := _glow(Color(walls[rng.randi() % walls.size()]), 0.12)
	var floor_c := _glow(Color(["#a8784e", "#8d6a4a", "#c9b79c", "#7d8a8f"][rng.randi() % 4]), 0.1)
	var hw := w * 0.5
	var z0 := -0.12                               # cephenin hemen arkası
	var z1 := -d
	# İçe bakan yüzler
	_q(st, [Vector3(-hw, 0, z1), Vector3(hw, 0, z1), Vector3(hw, ROOM_H, z1), Vector3(-hw, ROOM_H, z1)], Vector3(0, 0, 1), wall)
	_q(st, [Vector3(-hw, 0, z0), Vector3(-hw, 0, z1), Vector3(-hw, ROOM_H, z1), Vector3(-hw, ROOM_H, z0)], Vector3(1, 0, 0), _shade(wall, 0.92))
	_q(st, [Vector3(hw, 0, z1), Vector3(hw, 0, z0), Vector3(hw, ROOM_H, z0), Vector3(hw, ROOM_H, z1)], Vector3(-1, 0, 0), _shade(wall, 0.92))
	_q(st, [Vector3(-hw, 0.02, z0), Vector3(hw, 0.02, z0), Vector3(hw, 0.02, z1), Vector3(-hw, 0.02, z1)], Vector3(0, 1, 0), floor_c)
	_q(st, [Vector3(-hw, ROOM_H, z1), Vector3(hw, ROOM_H, z1), Vector3(hw, ROOM_H, z0), Vector3(-hw, ROOM_H, z0)], Vector3(0, -1, 0), _glow(Color("#f4f1ea"), 0.15))
	var animals: Array = []
	if shop:
		# Arka duvarda mal rafları, yan tarafta tezgâh ve kasiyer
		for y: float in [0.6, 1.2, 1.8]:
			_box(st, Vector3(0, y, z1 + 0.2), Vector3(w - 0.4, 0.05, 0.4), _glow(Color("#8a8f94"), 0.1))
			var x := -hw + 0.4
			while x < hw - 0.4:
				var c := Color(["#e05a6a", "#f0b44c", "#7cc6b0", "#8b5fbf", "#4f9a4a", "#4d79a8"][rng.randi() % 6])
				var h := rng.randf_range(0.15, 0.3)
				_box(st, Vector3(x, y + 0.025 + h * 0.5, z1 + 0.2), Vector3(0.18, h, 0.2), _glow(c, 0.15))
				x += 0.26
		# Tezgâh ve kasiyer bir vitrin bölmesinin arkasında (kapının yanında)
		var bays: Array = slot.get("bays", [])
		var cx: float = clampf(float(bays[0]) if not bays.is_empty() else 0.0, -hw + 0.9, hw - 0.9)
		_box(st, Vector3(cx, 0.48, z0 - 1.0), Vector3(1.6, 0.95, 0.6), _glow(Color("#a8744a"), 0.1))
		_box(st, Vector3(cx + 0.3, 1.07, z0 - 1.0), Vector3(0.4, 0.25, 0.3), _glow(Color("#3a3a42"), 0.1))
		animals.append([Vector3(cx, 0.0, z0 - 1.65), "idle", false])
	else:
		# Masalar: masada oturup çalışan hayvanlar (pencereye dönük)
		# Her pencere bölmesinin arkasında bir masa (en çok iki)
		var bays: Array = slot.get("bays", [0.0])
		for i in mini(bays.size(), 2):
			var dx := clampf(float(bays[i]) + rng.randf_range(-0.25, 0.25), -hw + 0.7, hw - 0.7)
			var dz := z0 - 1.1
			_box(st, Vector3(dx, 0.74, dz), Vector3(1.2, 0.05, 0.6), _glow(Color("#8a5a3c"), 0.1))
			for sx: float in [-0.55, 0.55]:
				_box(st, Vector3(dx + sx, 0.36, dz), Vector3(0.05, 0.72, 0.55), _glow(Color("#6b4630"), 0.1))
			_box(st, Vector3(dx + 0.3, 0.86, dz - 0.1), Vector3(0.36, 0.2, 0.03), _glow(Color("#3a3a42"), 0.1))
			_box(st, Vector3(dx + 0.3, 0.86, dz - 0.085), Vector3(0.32, 0.17, 0.01), _glow(Color("#9fd8f5"), 0.9))
			_box(st, Vector3(dx, 0.45, dz - 0.75), Vector3(0.45, 0.06, 0.45), _glow(Color("#3f5f7f"), 0.1))
			if rng.randf() < 0.85:
				animals.append([Vector3(dx, 0.47, dz - 0.75), "drive", true])
		if rng.randf() < 0.7:
			_box(st, Vector3(-hw + 0.35, 0.25, z1 + 0.35), Vector3(0.3, 0.5, 0.3), _glow(Color("#b5644a"), 0.1))
			_box(st, Vector3(-hw + 0.35, 0.75, z1 + 0.35), Vector3(0.45, 0.5, 0.45), _glow(Color("#4f9a4a"), 0.1))
	var mi := MeshInstance3D.new()
	var mesh := st.commit()
	mesh.surface_set_material(0, _vc_mat)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	for a in animals:
		_add_animal(root, rng, a[0], a[1], a[2])
	return root


## Hayvan: sokaktaki NPC modeli; masada oturur ("drive" pozu klavye başında gibi) ya da tezgâhta durur.
## Pencereye (sokağa) bakar.
func _add_animal(root: Node3D, rng: RandomNumberGenerator, pos: Vector3, anim: String, seated: bool) -> void:
	var sp := NpcCatalog.pick_species(rng)
	var recipe := NpcCatalog.make_recipe(rng, sp)
	recipe.parts = recipe.parts.filter(func(p): return not String(p).begins_with("tur_kuyruk"))
	var holder := Node3D.new()
	holder.rotation_degrees.y = 180.0       # model -Z'ye bakar; oda +Z (sokak) tarafına çevrilir
	root.add_child(holder)
	var model := Npc.build_model(recipe, _mats)
	holder.add_child(model)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation(anim):
		ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		ap.play(anim)
		ap.seek(rng.randf() * 2.0, true)
	holder.position = pos
	if seated and ap:
		# Oturuş: kalça sandalye oturağına gelsin (sürücü yerleştirmesindeki gibi)
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var hips := skel.find_bone("hips")
		if hips >= 0:
			var to_holder := holder.global_transform.affine_inverse() * skel.global_transform
			var hp := to_holder * skel.get_bone_global_pose(hips).origin
			holder.position = pos - Vector3(0, hp.y, 0) + Vector3(0, 0.08, 0)


## İç mekân rengi: gün ışığında içerisi dışarıdan loş görünür (ROOM_DIM), g kadar kendi ışığı
static func _glow(c: Color, g: float) -> Color:
	return Color(c.r * ROOM_DIM, c.g * ROOM_DIM, c.b * ROOM_DIM, 1.0 - g)


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func _q(st: SurfaceTool, ps: Array, n: Vector3, col: Color) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (ps[1] - ps[0]).cross(ps[2] - ps[0]).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(ps[k])


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)]],
		[Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
		[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
	]
	for f in faces:
		var ps := []
		for q in f[1]:
			ps.append(c + h * q)
		_q(st, ps, f[0], col)
