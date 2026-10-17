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
	"sinek": preload("res://assets/npc/sinek.glb"),
	"papagan": preload("res://assets/npc/papagan.glb"),
	"tilki": preload("res://assets/npc/tilki.glb"),
	"aslan": preload("res://assets/npc/aslan.glb"),
}
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")

enum State { WALK, IDLE, STUMBLE, SIT }

var recipe: Dictionary
var speed := 1.2
var state: int = State.IDLE
var velocity := Vector3.ZERO
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0
var path_ids := PackedInt64Array()    # yaya ağı düğümleri (yaya geçidi kenarlarını tanımak için)
var cross_index := -1                 # karşıya geçişi onaylanan yol parçası
var far := false                      # kameradan uzak: gizli, animasyon durur
var ground_exclude: Array[RID] = []   # zemin ışınının yok sayacağı gövdeler (oyuncu)
var avoid_side := 1.0                 # engelden hangi yandan dolanıyor
var avoid_t := 0.0                    # dolanma yönünü koruma süresi
## Zemin ışını en fazla bu kadar yukarıdan başlar: bankın, arabanın, kutunun üstüne çıkmaz
## (yalnız kaldırım gibi alçak basamaklar)
const STEP_UP := 0.45
## Bankta: rezerve ettiği yer (Banklar), oturma pozunda kalçanın köke göre yeri
var bench_seat := -1
var sit_hip := Vector3.INF
## Çocuk: yetişkin modelinin küçültülmüşü (baş ve eller büyük, scripts/npc/cocuk_oran.gd)
const CHILD_SCALE := 0.58
var child := false
var parent: Npc = null                # çocuksa elinden tuttuğu ebeveyn
var kid: Npc = null                   # ebeveynse elinden tuttuğu çocuk
var hand: ElTut = null                # el ele tutuşan kol
var role := ""                        # parkta: "kos", "salincak", "kaydirak", "tahterevalli", "bank"
var role_t := 0.0
var role_data: Dictionary = {}
var _hop_t := -1.0                    # yerinde zıplama (sn), _hop_len boyunca
var _hop_len := 0.45
var _hop_h := 0.25

var _model: Node3D
var _anim: AnimationPlayer
var _timer := 0.0
var _yaw := 0.0
var _anim_speed := 1.0                 # modelin 1x yürüyüşündeki hız (boy ölçeğiyle)
var _springs: SpringBoneSimulator3D    # kulak / kuyruk / hortum yaylanması
var _buzz: WingBuzz                    # sinek kanatlarının vızıldaması
var _ground_snap := true               # görünür olunca zemine bir anda otur


## materials: renk -> paylaşılan malzeme önbelleği (çizim çağrısı ve bellek için)
func setup(p_recipe: Dictionary, materials: Dictionary, is_child := false) -> void:
	recipe = p_recipe
	child = is_child
	speed = recipe.speed
	_anim_speed = recipe.anim_speed
	_model = build_model(recipe, materials)
	if child:
		_model.scale *= CHILD_SCALE
		_anim_speed *= CHILD_SCALE
		speed *= 0.85
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	for n in ["walk", "idle", "idle_look", "otur"]:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_measure_sit()
	_anim.play("idle")
	_anim.seek(randf() * 2.0, true)
	_setup_springs(recipe.springs)
	if not recipe.buzz.is_empty():
		_buzz = WingBuzz.new()
		_buzz.bones = PackedStringArray(recipe.buzz)
		_model.find_children("*", "Skeleton3D", true, false)[0].add_child(_buzz)
	if child:
		_model.find_children("*", "Skeleton3D", true, false)[0].add_child(CocukOran.new())


## El ele tutuşacak kol ("L" / "R"): ElTut düzenleyicisi
func add_hand(side: String) -> ElTut:
	if hand == null:
		hand = ElTut.new()
		hand.side = side
		_model.find_children("*", "Skeleton3D", true, false)[0].add_child(hand)
	return hand


## Yerinde zıplama (çocuklar parkta)
func hop(height := 0.25, length := 0.45) -> void:
	_hop_t = 0.0
	_hop_h = height
	_hop_len = length


func hopping() -> bool:
	return _hop_t >= 0.0


## Parkta dışarıdan oturtulup taşınan (salıncak, kaydırak, tahterevalli): kalça hip'e gelir
func place_sit(hip: Vector3, facing: Vector3) -> void:
	_yaw = atan2(-facing.x, -facing.z)
	rotation.y = _yaw
	global_position = hip + Vector3.UP * 0.03 - Basis(Vector3.UP, _yaw) * sit_hip * (1.0 if sit_hip != Vector3.INF else 0.0)
	velocity = Vector3.ZERO
	if state != State.SIT:
		_timer = 1e6
		_set_state(State.SIT)


func stand_up() -> void:
	if state == State.SIT:
		_set_state(State.IDLE)
		_timer = 0.0


## Boy (kök yerden başın tepesine yaklaşık; çocukta küçük)
func size_k() -> float:
	return CHILD_SCALE if child else 1.0


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


## Tarife göre giydirilmiş ve boyanmış model (yayalar ve araba sürücüleri kullanır).
static func build_model(recipe: Dictionary, materials: Dictionary) -> Node3D:
	var model: Node3D = MODELS[recipe.species].instantiate()
	model.rotation_degrees.y = 180.0   # Blender'da -Y'ye bakıyor
	model.scale = recipe.scale
	_keep_parts(model, recipe.parts)
	_paint(model, recipe.colors, materials)
	return model


## Seçilmeyen parçaları sil (gizli parçalar da işlemci harcar).
static func _keep_parts(node: Node, keep: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			if not keep.has(String(child.name)):
				child.queue_free()
		else:
			_keep_parts(child, keep)


static func _paint(node: Node, colors: Dictionary, materials: Dictionary) -> void:
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

func set_path(p: PackedVector3Array, ids := PackedInt64Array()) -> void:
	path = p
	path_ids = ids
	path_index = 0
	cross_index = -1
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
	if _buzz:
		_buzz.buzz(0.9)
	_timer = _anim.get_animation("stumble").length
	_set_state(State.STUMBLE)


## Oturma pozunda kalça kemiğinin köke göre yeri (banka oturtmak için)
func _measure_sit() -> void:
	if not _anim.has_animation("otur"):
		return
	var skel: Skeleton3D = _model.find_children("*", "Skeleton3D", true, false)[0]
	var hips := skel.find_bone("hips")
	if hips < 0:
		return
	_anim.play("otur")
	_anim.seek(0.0, true)
	var to_root := global_transform.affine_inverse() * skel.global_transform
	sit_hip = to_root * skel.get_bone_global_pose(hips).origin
	_anim.play("idle")


## Bu boyda banka oturabilir mi (kalçası oturaktan yukarıda kalmayacak kadar kısa olmalı)
func can_sit(seat_h: float) -> bool:
	return sit_hip != Vector3.INF and sit_hip.y <= seat_h + 0.06


## Banka otur: hip = oturağın üstündeki kalça noktası, facing = bakış yönü
func sit_at(hip: Vector3, facing: Vector3, seconds: float) -> void:
	_yaw = atan2(-facing.x, -facing.z)
	rotation.y = _yaw
	global_position = hip + Vector3.UP * 0.05 - Basis(Vector3.UP, _yaw) * sit_hip
	velocity = Vector3.ZERO
	_timer = seconds
	_set_state(State.SIT)


func sit_done() -> bool:
	return state == State.SIT and _timer <= 0.0


func is_sitting() -> bool:
	return state == State.SIT


func is_busy() -> bool:
	return state == State.STUMBLE or state == State.SIT


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


## Dışarıdan sürülen hareket (ebeveynini izleyen ya da parkta oynayan çocuk): yön verilince
## yürür, verilmeyince bekler (yol izleyen NPC'lerin durum makinesi kullanılmaz)
func move(delta: float, steer: Vector3) -> void:
	if state != State.STUMBLE and state != State.SIT:
		var want := State.WALK if steer.length() > 0.05 else State.IDLE
		if state != want:
			state = want
			if want == State.IDLE:
				_timer = 1e6
	tick(delta, steer)


func tick(delta: float, steer: Vector3) -> void:
	if state == State.SIT:
		_timer -= delta
		if not far:
			_play("otur")
			_anim.speed_scale = 1.0
		return
	if state == State.STUMBLE or state == State.IDLE:
		_timer -= delta
		velocity = velocity.move_toward(Vector3.ZERO, 6.0 * delta)
	else:
		velocity = velocity.move_toward(steer, (6.0 if child else 4.0) * delta)
	global_position += velocity * delta
	_follow_ground(delta)
	if _hop_t >= 0.0:
		_hop_t += delta
		var k := _hop_t / _hop_len
		if k >= 1.0:
			_hop_t = -1.0
		else:
			global_position.y += 4.0 * _hop_h * k * (1.0 - k)

	var v := Vector3(velocity.x, 0.0, velocity.z)
	if state != State.STUMBLE and v.length() > 0.15:
		_yaw = lerp_angle(_yaw, atan2(-v.x, -v.z), 1.0 - exp(-8.0 * delta))
		rotation.y = _yaw

	if far:
		return
	if state == State.WALK and v.length() > 0.1:
		_play("walk")
		_anim.speed_scale = clampf(v.length() / _anim_speed, 0.5, 2.6 if child else 1.8)
	elif state != State.STUMBLE:
		_play(_idle_anim)
		_anim.speed_scale = 1.0


## Ayaklar zeminde: görünürken yukarıdan aşağı ışınla gerçek yürüme yüzeyini bul. Işın yüksekten
## başlar: NPC bir şekilde zeminin altına düşmüşse de yüzeyi bulur (dağ yamaçlarında yol
## noktaları zeminden alçakta kalabiliyordu, kısa ışın zemini göremeyip NPC gömülüyordu).
## Lamba, tabela, bank gibi şeylerin tepesi yürüme yüzeyi sayılmaz; şehir yüzeyleri (merdiven,
## yükselti) yalnız bir basamak yukarıdaysa.
func _follow_ground(delta: float) -> void:
	if not far:
		var gy := _ground_y(global_position)
		if not is_nan(gy):
			if _ground_snap or global_position.y < gy - 0.3:
				global_position.y = gy
				_ground_snap = false
			else:
				global_position.y = lerpf(global_position.y, gy, 1.0 - exp(-20.0 * delta))
			return
	if path_index < path.size():
		global_position.y = lerpf(global_position.y, path[path_index].y, 1.0 - exp(-8.0 * delta))


const WALKABLE := ["Kaldirim", "Yol", "Kavsak", "Meydan", "Arazi", "Iskele"]


func _ground_y(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = ground_exclude.duplicate()
	for k in 5:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z), Vector3(p.x, p.y - 12.0, p.z), 0xFFFFFFFF, excl)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var c: Object = hit.collider
		var ok := false
		if not (c is Araba) and c is Node:
			var nm := String((c as Node).name)
			for w in WALKABLE:
				if nm.begins_with(w):
					ok = true
					break
			if not ok and (c as Node).has_meta("surface") and hit.normal.y > 0.7 and hit.position.y < p.y + STEP_UP + 0.1:
				ok = true
		if ok:
			return hit.position.y
		excl.append(hit.rid)
	return NAN


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
	_ground_snap = true
	visible = not value
	_anim.active = not value
	if _springs:
		_springs.active = not value
	if _buzz:
		_buzz.active = not value
