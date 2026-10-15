class_name Npc
extends Node3D
## Tek bir hayvan NPC: modelden seçili parçaları tutar, boyar; yürür, bekler,
## kaykayla çarpılınca affallar ve yoluna devam eder.
## Yol ve kalabalık mantığı NpcCrowd'da; NPC kendisine verilen yolu izler.

## Her türün kendi modeli (gövdesi, kafası, iskeleti, hareketleri ve ona biçilmiş kıyafetleri)
const MODELS := {
	"zurafa": preload("res://assets/npc/zurafa.glb"),
	"fil": preload("res://assets/npc/fil.glb"),
	"penguen": preload("res://assets/npc/penguen.glb"),
	"guvercin": preload("res://assets/npc/guvercin.glb"),
	"kedi": preload("res://assets/npc/kedi.glb"),
	"kopek": preload("res://assets/npc/kopek.glb"),
	"tavsan": preload("res://assets/npc/tavsan.glb"),
	"sican": preload("res://assets/npc/sican.glb"),
	"kurbaga": preload("res://assets/npc/kurbaga.glb"),
}
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")

enum State { WALK, IDLE, STUMBLE }

var recipe: Dictionary
var speed := 1.2
var state: int = State.IDLE
var velocity := Vector3.ZERO
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0
var far := false                      # kameradan uzak: gizli, animasyon durur

var _model: Node3D
var _anim: AnimationPlayer
var _timer := 0.0
var _yaw := 0.0
var _anim_speed := 1.0                 # modelin 1x yürüyüşündeki hız (boy ölçeğiyle)
var _springs: SpringBoneSimulator3D    # kulak / kuyruk / hortum yaylanması


## materials: renk -> paylaşılan malzeme önbelleği (çizim çağrısı ve bellek için)
func setup(p_recipe: Dictionary, materials: Dictionary) -> void:
	recipe = p_recipe
	speed = recipe.speed
	_anim_speed = recipe.anim_speed
	_model = MODELS[recipe.species].instantiate()
	_model.rotation_degrees.y = 180.0   # Blender'da -Y'ye bakıyor
	_model.scale = recipe.scale
	add_child(_model)
	_keep_parts(_model, recipe.parts)
	_paint(_model, recipe.colors, materials)
	_anim = _model.find_child("AnimationPlayer", true, false)
	for n in ["walk", "idle", "idle_look"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("idle")
	_anim.seek(randf() * 2.0, true)
	_setup_springs(recipe.springs)


## Kulak, kuyruk, hortum gibi zincirler: animasyonun üstüne fiziksel yaylanma
## (yürürken, dönerken, çarpılınca gecikmeli sallanır).
func _setup_springs(springs: Array) -> void:
	if springs.is_empty():
		return
	var skel: Skeleton3D = _model.find_children("*", "Skeleton3D", true, false)[0]
	_springs = SpringBoneSimulator3D.new()
	_springs.set_setting_count(springs.size())
	for i in springs.size():
		var s: Array = springs[i]
		_springs.set_root_bone_name(i, s[0])
		_springs.set_end_bone_name(i, s[1])
		_springs.set_extend_end_bone(i, true)
		_springs.set_end_bone_length(i, 0.05)
		_springs.set_stiffness(i, s[2])
		_springs.set_drag(i, s[3])
		_springs.set_gravity(i, s[4])
		_springs.set_radius(i, 0.01)
	skel.add_child(_springs)


## Seçilmeyen parçaları sil (gizli parçalar da işlemci harcar).
func _keep_parts(node: Node, keep: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if not keep.has(String(child.name)):
				child.queue_free()
		else:
			_keep_parts(child, keep)


func _paint(node: Node, colors: Dictionary, materials: Dictionary) -> void:
	if node is MeshInstance3D and not node.is_queued_for_deletion():
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var slot := String(src.resource_name) if src else ""
			var color: Color = colors.get(slot, src.albedo_color if src is BaseMaterial3D else Color.WHITE)
			var key := color.to_html()
			if not materials.has(key):
				var m := ShaderMaterial.new()
				m.shader = CHAR_SHADER
				m.set_shader_parameter("albedo", color)
				materials[key] = m
			node.set_surface_override_material(i, materials[key])
	for child in node.get_children():
		_paint(child, colors, materials)


# ---------- Davranış (NpcCrowd her fizik karesinde çağırır) ----------

func set_path(p: PackedVector3Array) -> void:
	path = p
	path_index = 0
	_set_state(State.WALK)


func idle_for(seconds: float) -> void:
	_timer = seconds
	_set_state(State.IDLE)


## Kaykayla çarpılınca: çarpanın yönüne dön, geriye sendele, sonra devam et.
func stumble(from_pos: Vector3) -> void:
	if state == State.STUMBLE:
		return
	var to := from_pos - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_yaw = atan2(-to.x, -to.z)
		rotation.y = _yaw
	velocity = Vector3.ZERO
	_timer = _anim.get_animation("stumble").length
	_set_state(State.STUMBLE)


func is_busy() -> bool:
	return state == State.STUMBLE


## Bir sonraki yol noktasına doğru istenen hız (kalabalık bunu kaçınmayla birleştirir).
func desired_velocity() -> Vector3:
	if state != State.WALK or path_index >= path.size():
		return Vector3.ZERO
	var to := path[path_index] - global_position
	to.y = 0.0
	if to.length() < 0.6:
		path_index += 1
		if path_index >= path.size():
			return Vector3.ZERO
		to = path[path_index] - global_position
		to.y = 0.0
	return to.normalized() * speed


func reached_end() -> bool:
	return state == State.WALK and path_index >= path.size()


func tick(delta: float, steer: Vector3) -> void:
	if state == State.STUMBLE or state == State.IDLE:
		_timer -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 6.0 * delta)
	else:
		velocity = velocity.move_toward(steer, 4.0 * delta)
	global_position += velocity * delta
	# Zemin yüksekliği yol noktalarından (düz meydan; arnavut kaldırımı 1 cm)
	if path_index < path.size():
		global_position.y = lerpf(global_position.y, path[path_index].y, 1.0 - exp(-8.0 * delta))

	var v := Vector3(velocity.x, 0.0, velocity.z)
	if state != State.STUMBLE and v.length() > 0.15:
		_yaw = lerp_angle(_yaw, atan2(-v.x, -v.z), 1.0 - exp(-8.0 * delta))
		rotation.y = _yaw

	if far:
		return
	if state == State.WALK and v.length() > 0.1:
		_play("walk")
		_anim.speed_scale = clampf(v.length() / _anim_speed, 0.5, 1.8)
	elif state != State.STUMBLE:
		_play(_idle_anim)
		_anim.speed_scale = 1.0


func stumble_done() -> bool:
	return state == State.STUMBLE and _timer <= 0.0


func idle_done() -> bool:
	return state == State.IDLE and _timer <= 0.0


var _idle_anim := "idle"


func _set_state(s: int) -> void:
	state = s
	if s == State.STUMBLE:
		_anim.speed_scale = 1.0
		_anim.play("stumble", 0.08)
	elif s == State.IDLE:
		_idle_anim = "idle_look" if randf() < 0.45 else "idle"


func _play(name: String) -> void:
	if _anim.current_animation != name:
		_anim.play(name, 0.25)


## Uzaktaki NPC'leri gizle ve animasyonlarını durdur (performans).
func set_far(value: bool) -> void:
	if value == far:
		return
	far = value
	visible = not value
	_anim.active = not value
	if _springs:
		_springs.active = not value
