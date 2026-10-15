extends Node3D
## Geçici (placeholder) karakter + kaykay görseli.
## Gerçek model gelene kadar basit şekillerle: önemli olan itme ayağının
## parmağa senkron hareket etmesi, dönüşte eğilme ve inişte esneme.
##
## Yerel eksenler: kaykayın ucu -Z yönünde. Karakter önüne (-Z) bakar, kamera
## sırtını ve sırt çantasını görür. Sağ ayak kaykayın üstünde kalır, sol ayak
## kaykayın solunda yere basıp geriye doğru iter.

const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")

@export var lean_angle := 18.0          # dönüşte en fazla eğilme (derece)
@export var align_sharpness := 14.0

const DECK_Y := 0.12
# "FRONT" = kaykayda kalan sağ ayak, "BACK" = iten sol ayak
const FRONT_FOOT := Vector3(0.05, DECK_Y + 0.03, -0.1)
const BACK_FOOT_ON_BOARD := Vector3(-0.05, DECK_Y + 0.03, 0.2)
const STROKE_START := Vector3(-0.27, 0.04, -0.15)
const STROKE_END := Vector3(-0.27, 0.04, 0.7)
const BRAKE_FOOT := Vector3(-0.24, 0.04, 0.45)
const HIP_IDLE := Vector3(0.0, 0.62, 0.04)
const HIP_PUSH := Vector3(0.05, 0.5, -0.04)
const HIP_BRAKE := Vector3(0.03, 0.52, 0.02)
const HIP_GRIND := Vector3(0.0, 0.5, 0.02)
const PUSH_TILT := -0.3      # itme sırasında gövdenin öne eğilmesi (radyan)

var controller: SkateController

var _board: Node3D
var _rider: Node3D          # kalça / gövde / kafa
var _back_foot: MeshInstance3D
var _front_foot: MeshInstance3D
var _back_leg: MeshInstance3D
var _front_leg: MeshInstance3D

var _foot_pos := BACK_FOOT_ON_BOARD
var _hip_pos := HIP_IDLE
var _squash := 0.0
var _lean := 0.0
var _tilt := 0.0
var _sparks: CPUParticles3D
var _time := 0.0


func _ready() -> void:
	controller = get_parent() as SkateController
	controller.landed.connect(_on_landed)
	controller.ollied.connect(func(): _squash = -0.25)
	_build()


func _physics_process(delta: float) -> void:
	_time += delta
	_align(delta)
	_animate_body(delta)
	_update_sparks()


func _align(delta: float) -> void:
	var up := controller.ground_normal
	var fwd := controller.forward_on_ground
	fwd = (fwd - up * fwd.dot(up)).normalized()
	if fwd.length_squared() < 0.5:
		return
	var target := Basis.looking_at(fwd, up)

	var lean_target: float
	if controller.grinding:
		# Boardslide: kaykay raya dik döner
		if controller.grind_style == 1:
			target = target * Basis(Vector3.UP, PI * 0.5)
		# Rayda denge: hafif sağa sola salınım
		lean_target = sin(_time * 5.0) * 0.07 + sin(_time * 8.3) * 0.03
	else:
		# Dönüşe doğru eğil (hızla artar)
		var speed01 := clampf(absf(controller.speed) / 6.0, 0.0, 1.0)
		lean_target = -controller.steer * deg_to_rad(lean_angle) * speed01
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-10.0 * delta))
	target = target * Basis(Vector3(0, 0, 1), _lean)

	var current := global_basis.orthonormalized()
	global_basis = current.slerp(target, 1.0 - exp(-align_sharpness * delta))


func _animate_body(delta: float) -> void:
	var inp := SkateInput
	var foot_target := BACK_FOOT_ON_BOARD
	var hip_target := HIP_IDLE
	var foot_sharp := 12.0
	var tilt_target := 0.0

	if controller.grinding:
		hip_target = HIP_GRIND
		tilt_target = -0.12
	elif controller.grounded:
		if inp.gesture == SkateInput.Gesture.PUSH and inp.foot_contact:
			# Ayak doğrudan parmağın konumunu izler
			foot_target = STROKE_START.lerp(STROKE_END, inp.push_progress)
			hip_target = HIP_PUSH
			tilt_target = PUSH_TILT
			foot_sharp = 30.0
		elif inp.gesture == SkateInput.Gesture.REVERSE and inp.foot_contact:
			# Geri itme: ayak arkadan öne doğru yere sürtülür
			foot_target = STROKE_END.lerp(STROKE_START, inp.push_progress) + Vector3(0, 0, -0.1)
			hip_target = HIP_BRAKE
			tilt_target = 0.2
			foot_sharp = 30.0
		elif inp.gesture == SkateInput.Gesture.PUSH or inp.gesture == SkateInput.Gesture.REVERSE:
			# Vuruş bitti, parmak hâlâ ekranda: ayak havada bekler
			foot_target = STROKE_END + Vector3(0, 0.12, -0.15)
			hip_target = HIP_PUSH
			tilt_target = PUSH_TILT * 0.6
		elif inp.gesture == SkateInput.Gesture.BRAKE:
			foot_target = BRAKE_FOOT
			hip_target = HIP_BRAKE
			tilt_target = 0.15
			foot_sharp = 20.0

	# Kaykaya dönerken ayağı hafifçe havaya kaldır (yay çizerek)
	var returning := foot_target == BACK_FOOT_ON_BOARD and _foot_pos.distance_to(foot_target) > 0.08
	if returning:
		foot_target.y += 0.12

	_foot_pos = _foot_pos.lerp(foot_target, 1.0 - exp(-foot_sharp * delta))
	_hip_pos = _hip_pos.lerp(hip_target, 1.0 - exp(-10.0 * delta))
	_tilt = lerpf(_tilt, tilt_target, 1.0 - exp(-8.0 * delta))

	# İniş / ollie esnemesi
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-8.0 * delta))
	var crouch := Vector3(0, -absf(_squash) * 0.5, 0)

	_rider.position = _hip_pos + crouch
	_rider.rotation.x = _tilt
	_back_foot.position = _foot_pos
	_place_limb(_back_leg, _rider.position + Vector3(-0.08, -0.02, 0), _foot_pos)
	_place_limb(_front_leg, _rider.position + Vector3(0.08, -0.02, 0), FRONT_FOOT)
	_board.position.y = 0.0


func _update_sparks() -> void:
	_sparks.emitting = controller.grinding
	if controller.grinding:
		var back := -controller.grind_dir
		if absf(back.y) < 0.99:
			_sparks.global_basis = Basis.looking_at(back, Vector3.UP)


func _on_landed(impact: float) -> void:
	_squash = clampf(impact * 0.06, 0.0, 0.35)


# ---------- Yapım ----------

func _build() -> void:
	_board = Node3D.new()
	add_child(_board)
	_mesh_box(_board, Vector3(0.24, 0.03, 0.82), Vector3(0, DECK_Y, 0), Color(0.15, 0.75, 0.85))
	_mesh_box(_board, Vector3(0.24, 0.031, 0.1), Vector3(0, DECK_Y + 0.025, -0.4), Color(0.15, 0.75, 0.85), 18.0)
	_mesh_box(_board, Vector3(0.24, 0.031, 0.1), Vector3(0, DECK_Y + 0.025, 0.4), Color(0.15, 0.75, 0.85), -18.0)
	for z in [-0.27, 0.27]:
		for x in [-0.1, 0.1]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.035
			cyl.height = 0.04
			cyl.radial_segments = 8
			wheel.mesh = cyl
			wheel.material_override = _mat(Color(1.0, 0.9, 0.3))
			wheel.position = Vector3(x, 0.035, z)
			wheel.rotation_degrees.z = 90.0
			_board.add_child(wheel)

	# Karakter: büyük kafalı çocuk (chibi oranlar)
	_rider = Node3D.new()
	add_child(_rider)
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.16
	cap.height = 0.5
	cap.radial_segments = 8
	cap.rings = 2
	torso.mesh = cap
	torso.material_override = _mat(Color(1.0, 0.35, 0.3))
	torso.position = Vector3(0, 0.22, 0)
	_rider.add_child(torso)

	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	sph.radial_segments = 10
	sph.rings = 6
	head.mesh = sph
	head.material_override = _mat(Color(1.0, 0.8, 0.62))
	head.position = Vector3(0, 0.66, 0)
	_rider.add_child(head)
	# Şapka + siper (karakterin baktığı yönü gösterir: -Z)
	_mesh_box(head, Vector3(0.4, 0.12, 0.36), Vector3(0, 0.15, 0), Color(0.25, 0.45, 1.0))
	_mesh_box(head, Vector3(0.3, 0.03, 0.2), Vector3(0, 0.1, -0.22), Color(0.25, 0.45, 1.0))
	for x in [-0.08, 0.08]:
		_mesh_box(head, Vector3(0.04, 0.07, 0.02), Vector3(x, 0.0, -0.21), Color(0.1, 0.1, 0.15))
	# Sırt çantası (kamera arkadan görür)
	_mesh_box(_rider, Vector3(0.28, 0.32, 0.14), Vector3(0, 0.28, 0.19), Color(0.98, 0.75, 0.2))

	_back_leg = _limb(Color(0.2, 0.3, 0.55))
	_front_leg = _limb(Color(0.2, 0.3, 0.55))
	_back_foot = _mesh_box(self, Vector3(0.1, 0.07, 0.17), _foot_pos, Color(0.95, 0.95, 0.95))
	_front_foot = _mesh_box(self, Vector3(0.1, 0.07, 0.17), FRONT_FOOT, Color(0.95, 0.95, 0.95))

	# Grind kıvılcımları (dünya uzayında kalır, arkada iz bırakır)
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 28
	_sparks.lifetime = 0.35
	_sparks.local_coords = false
	_sparks.position = Vector3(0, 0.03, 0)
	_sparks.direction = Vector3(0, 0.5, -1)
	_sparks.spread = 35.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 4.0
	_sparks.gravity = Vector3(0, -12, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.2
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.025, 0.025, 0.06)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.8, 0.3)
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	add_child(_sparks)


func _limb(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.05
	cyl.height = 1.0
	cyl.radial_segments = 6
	mi.mesh = cyl
	mi.material_override = _mat(color)
	add_child(mi)
	return mi


func _place_limb(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.001:
		return
	var y := dir / length
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, tilt_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation_degrees.x = tilt_deg
	parent.add_child(mi)
	return mi


func _mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CHAR_SHADER
	m.set_shader_parameter("albedo", color)
	return m
