class_name Araba
extends AnimatableBody3D
## Trafikteki bir araba: model (tools/blender/araba_build.py), boya, dönen tekerlekler, fren
## lambaları ve koltukta direksiyon çeviren bir hayvan sürücü. Hareketi Trafik yöneticisi verir
## (şerit üstünde konum + hız); gövde fizik dünyasında oyuncuyu iter (AnimatableBody).

const MODELS := {
	"hatchback": {
		"scene": preload("res://assets/araba/hatchback.glb"),
		"colors": [Color(0.78, 0.16, 0.12), Color(0.45, 0.7, 0.86), Color(0.92, 0.86, 0.7), Color(0.28, 0.52, 0.3), Color(0.95, 0.5, 0.12)],
		"half": Vector3(0.83, 0.7, 1.95), "roof": 1.38, "weight": 1.0,
	},
	"minibus": {
		"scene": preload("res://assets/araba/minibus.glb"),
		"colors": [Color(0.98, 0.78, 0.1), Color(0.93, 0.93, 0.9), Color(0.14, 0.2, 0.42), Color(0.5, 0.1, 0.14), Color(0.55, 0.85, 0.7)],
		"half": Vector3(0.98, 1.1, 2.6), "roof": 2.1, "weight": 0.55,
	},
	"kamyonet": {
		"scene": preload("res://assets/araba/kamyonet.glb"),
		"colors": [Color(0.92, 0.92, 0.9), Color(0.55, 0.1, 0.08), Color(0.45, 0.46, 0.32), Color(0.5, 0.52, 0.55), Color(0.4, 0.62, 0.85)],
		"half": Vector3(0.9, 0.86, 2.45), "roof": 1.72, "weight": 0.7,
	},
}
## İki yüzlü: kamera araca girince tavan ve kapılar içeriden de görünür
const CHAR_SHADER := preload("res://shaders/toon_char_2s.gdshader")
## Oyuncu tutunurken kökü arka tamponun bu kadar gerisinde (karakter_rig.py "tutun" eli)
const SKITCH_GAP := 0.75
## Kabine sığmayan türler sürücü olmaz
const NO_DRIVE := ["zurafa"]

var model_key := "hatchback"
var half := Vector3.ONE
var speed := 0.0
var fwd := Vector3.FORWARD       # gidiş yönü (yatay)

# Trafik yöneticisinin tuttuğu sürüş durumu
var lane := -1
var s := 0.0
var route: Array[int] = []
var blocked_by: Araba = null
var hold := 0.0                  # > 0: çarpışma sonrası bekleme
var decide_phase := 0
var cached_gap := 1e9
var cached_lead_v := 0.0
var cached_vmax := 10.0
var reason := ""                 # son karar: neden yavaşlıyor (hata ayıklama)

var _wheels: Array[Node3D] = []
var _front: Array[Node3D] = []
var _wheel_r := 0.3
var _spin := 0.0
var _stop_mi: MeshInstance3D
var _stop_on: ShaderMaterial
var _stop_off: ShaderMaterial
var _braking := false
var _driver_anim: AnimationPlayer
var _model: Node3D
var _far := false


func setup(key: String, color_index: int, rng: RandomNumberGenerator, npc_materials: Dictionary) -> void:
	model_key = key
	var m: Dictionary = MODELS[key]
	half = m.half
	sync_to_physics = true
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, half.y + 0.05, 0)
	add_child(cs)
	set_meta("surface", "metal")

	_model = m.scene.instantiate()
	_model.rotation_degrees.y = 180.0   # Blender'da -Y'ye bakıyor; oyunda ileri -Z
	add_child(_model)
	_paint(_model, m.colors[color_index % m.colors.size()])
	for w in _model.find_children("Teker_*", "", true, false):
		_wheels.append(w)
		if String(w.name).begins_with("Teker_On"):
			_front.append(w)
	if not _wheels.is_empty():
		_wheel_r = _wheels[0].position.y
	_add_driver(rng, npc_materials, m.roof)


func _paint(node: Node, body_color: Color) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var slot := String(src.resource_name) if src else ""
			var color: Color = src.albedo_color if src is BaseMaterial3D else Color.WHITE
			if slot == "govde":
				color = body_color
			elif slot == "kasa":
				color = body_color.darkened(0.55)
			if slot == "cam":
				# Camlar yarı saydam: içerideki sürücü görünsün
				var glass := StandardMaterial3D.new()
				glass.albedo_color = Color(0.32, 0.42, 0.52, 0.38)
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.roughness = 0.2
				glass.cull_mode = BaseMaterial3D.CULL_DISABLED
				node.set_surface_override_material(i, glass)
				continue
			var mat := ShaderMaterial.new()
			mat.shader = CHAR_SHADER
			mat.set_shader_parameter("albedo", color)
			node.set_surface_override_material(i, mat)
			if slot == "stop":
				_stop_mi = node
				_stop_off = mat
				_stop_on = ShaderMaterial.new()
				_stop_on.shader = CHAR_SHADER
				_stop_on.set_shader_parameter("albedo", Color(1.0, 0.18, 0.12))
		if String(node.name) == "Far":
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_paint(c, body_color)


## Koltuğa oturan sürücü: kalça kemiği koltuk noktasına, kafa tavana sığacak ölçekte.
func _add_driver(rng: RandomNumberGenerator, npc_materials: Dictionary, roof: float) -> void:
	var seat: Node3D = _model.find_child("Koltuk", true, false)
	if seat == null:
		return
	var species := NpcCatalog.pick_species(rng)
	for attempt in 8:
		if not NO_DRIVE.has(species):
			break
		species = NpcCatalog.pick_species(rng)
	if NO_DRIVE.has(species):
		return
	var recipe := NpcCatalog.make_recipe(rng, species)
	var driver := Npc.build_model(recipe, npc_materials)
	_model.add_child(driver)
	_driver_anim = driver.find_child("AnimationPlayer", true, false)
	if _driver_anim == null or not _driver_anim.has_animation("drive"):
		driver.queue_free()
		return
	_driver_anim.get_animation("drive").loop_mode = Animation.LOOP_LINEAR
	_driver_anim.play("drive")
	_driver_anim.seek(rng.randf() * 3.0, true)
	var skel: Skeleton3D = driver.find_children("*", "Skeleton3D", true, false)[0]
	var hips := skel.find_bone("hips")
	var head := skel.find_bone("head")
	if hips < 0:
		return
	# Oturmuş pozda kalça ve kafa, sürücü modelinin kendi (ölçeksiz) uzayında
	var to_driver := driver.global_transform.affine_inverse() * skel.global_transform
	var hp := to_driver * skel.get_bone_global_pose(hips).origin
	var hd := to_driver * skel.get_bone_global_pose(head).origin if head >= 0 else hp + Vector3(0, 0.6, 0)
	var seat_pos := _model.to_local(seat.global_position)
	var room := roof - seat_pos.y - 0.08
	var sc: Vector3 = recipe.scale
	var need := (hd.y - hp.y) * sc.y + 0.2
	if need > room:
		sc *= room / need
	# Sürücü araba modelinin içinde: ikisi de Blender yönünde, ek dönüş yok
	driver.transform = Transform3D(Basis.from_scale(sc), seat_pos - hp * sc)


## Konum ve yön (yönetici her fizik karesinde verir); tekerlekler, direksiyon, fren lambası.
func drive_to(pos: Vector3, forward: Vector3, up: Vector3, steer: float, braking: bool, delta: float) -> void:
	fwd = Vector3(forward.x, 0.0, forward.z).normalized()
	var z := -forward.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	global_transform = Transform3D(Basis(x, y, z), pos)
	if _far:
		return
	_spin = fmod(_spin + speed * delta / maxf(_wheel_r, 0.1), TAU)
	for w in _wheels:
		w.rotation = Vector3(_spin, 0.0, 0.0)
	for w in _front:
		w.rotation = Vector3(_spin, steer, 0.0)
	if braking != _braking and _stop_mi:
		_braking = braking
		_stop_mi.set_surface_override_material(0, _stop_on if braking else _stop_off)


## Uzaktayken sürücü animasyonu durur (performans).
func set_far(value: bool) -> void:
	if value == _far:
		return
	_far = value
	if _driver_anim:
		_driver_anim.active = not value


## Tutunma noktası: arka tamponun SKITCH_GAP gerisinde, yol yüksekliğinde.
func skitch_anchor() -> Vector3:
	return global_position - fwd * (half.z + SKITCH_GAP)


func forward() -> Vector3:
	return fwd
