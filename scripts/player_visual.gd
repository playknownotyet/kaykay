extends Node3D
## Oyuncu görseli: Blender'da üretilen karakter + kaykay modeli (assets/karakter/karakter.glb).
##
## - Görsel, kaykayın yönüne ve zemin eğimine hizalanır; dönüşte eğilir.
## - Animasyonlar bir AnimationTree ile yumuşak geçişlerle oynatılır.
##   Sürüşte yavaş/hızlı ve sola/sağa dönüş pozları hıza ve direksiyona göre
##   sürekli karışır: kollar ve gövde sürüşe canlı tepki verir.
## - Süzülürken yan duruş (sağ ayak önde, gövde yana); iterken ve itişler arasında
##   gövde öne döner, itme bitince yavaşça yana geri döner.
## - Dik yokuş aşağı yüksek hızda "tuck" (eller sırtta, gövde yatay).
## - Grind'de düz rayda alçak duruş, aşağı eğimli rayda dik duruş ve kalkık kol.
## - Kaykay iskeletin bir kemiği: binme/inme/elde taşıma animasyonun parçası.
## - İtme animasyonu kendi kendine oynamaz: her karede parmağın konumuna göre
##   sarılır, böylece sol ayak parmağı izler (geri itmede tersine).
## - Grind'de kıvılcım çıkar; boardslide'da tüm görsel 90° döner.
##
## Model kaynağı: tools/blender/karakter_model.py + karakter_rig.py

const MODEL := preload("res://assets/karakter/karakter.glb")
const CHAR_SHADER := preload("res://shaders/toon_char.gdshader")
const STATES := ["ride", "push", "push_ret", "brake", "crouch", "air", "ollie", "flip", "grind", "walk", "run", "stand_idle", "mount", "dismount", "dus", "tutun", "yaya_hava", "yaya_dus", "cantaya_at", "canta_ac", "canta_kapat", "canta_acik",
	"yaya_zipla", "yaya_inis", "eline_al", "cantaya_koy", "havada_cirpin", "otur", "muzik_cikar", "muzik_bak", "muzik_koy", "muzik_cikar_kisa", "muzik_kulaklik_cikar"]
const LOOPING := ["ride_idle", "ride_fast", "ride_turn_l", "ride_turn_r", "ride_ready", "ride_tuck", "brake", "air", "grind", "grind_down", "walk", "run", "stand_idle", "tutun", "yaya_hava", "canta_acik", "havada_cirpin", "elde_tut", "otur", "muzik_bak"]
## Ollie animasyonunda fiziksel sıçramanın olduğu an (karakter_rig.py OLLIE_POP_FRAME / 30)
const OLLIE_POP_TIME := 0.1
## İtmeden dönüş (ayak kaykaya geri biner): karakter_rig.py PUSH_RET_FRAMES / 30
const PUSH_RET_TIME := 10.0 / 30.0
## Yaya zıplaması ve inişi (karakter_rig.py YAYA_ZIPLA_FRAMES / YAYA_INIS_FRAMES)
const YAYA_ZIPLA_TIME := 12.0 / 30.0
const YAYA_INIS_TIME := 10.0 / 30.0

@export var lean_angle := 17.0          # dönüşte en fazla eğilme (derece)
@export var align_sharpness := 14.0
@export var anim_blend := 0.2
## Yürüme / koşu animasyonu 1x hızda kaç m/sn'ye denk geliyor (ayak kaymasın diye).
## karakter_rig.py'deki WALK / RUN ölçülerinden: 2 * amp / (duty * döngü süresi)
@export var walk_anim_speed := 1.273
@export var run_anim_speed := 3.667

@export_group("Kol sallanması")
## Yay sertliği ve sönüm: kollar ne kadar çabuk toparlanır / ne kadar salınır
@export var sway_stiffness := 38.0
@export var sway_damping := 7.0
## Hızla rüzgârda geriye itilme (radyan / m/sn)
@export var sway_wind := 0.016
## İvmede geride kalma, frende öne savrulma (radyan / m/sn²)
@export var sway_inertia := 0.045
## Dönüşte merkezkaç ile dışa açılma (radyan / m/sn²)
@export var sway_turn := 0.035
## Adımlarla gelen hafif sallanma
@export var sway_step := 0.06
@export var sway_max := 0.55
## Bu hızda (m/sn) "hızlı sürüş" pozu tam devrede.
@export var fast_ride_speed := 8.0

@export_group("Duruş")
## İtme bittikten sonra gövde bu kadar süre öne dönük kalır (sn), sonra yana döner
@export var push_face_hold := 0.55
## Öne dönme / yana geri dönme hızı (1/sn)
@export var face_in_rate := 10.0
@export var face_out_rate := 2.6
## Yüksek hız pozu: bu hızın (km/s) ve yokuş eğiminin (yükselme / yol) üstünde,
## bu kadar süre (sn) kesintisiz kalınca girer; altına düşünce çıkar.
## Adada yolların en dik yeri %9: serpantinin çoğu, şehirde yalnız birkaç dik sokak.
@export var tuck_kmh := 31.0
@export var tuck_grade := 0.06
@export var tuck_delay := 0.5
@export var tuck_exit_kmh := 26.0
@export var tuck_exit_grade := 0.035
## Grind: bu eğimin (yükselme / ray) üstündeki raylarda "aşağı ray" pozu tam devrede
@export var grind_down_grade := 0.25

var controller: SkateController

var _model: Node3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _push_len := 0.8
var _state := ""
var _land_timer := 0.0
var _sparks: CPUParticles3D
var _time := 0.0
var _lean := 0.0
var _speed_blend := 0.0
var _special := ""           # "ollie" / "flip": tek seferlik zıplama animasyonu
var _special_t := 0.0
var _special_len := 0.0
var _sway: ArmSway
# Kol yayı: x = arkaya, y = dışa; L ve R ayrı (dönüşte farklı tepki verir)
var _sway_pos := {"L": Vector2.ZERO, "R": Vector2.ZERO}
var _sway_vel := {"L": Vector2.ZERO, "R": Vector2.ZERO}
var _prev_speed := 0.0
var _prev_yaw := 0.0
var _step_phase := 0.0
var _air_t := 0.0            # kesintisiz havada geçen süre
var _ollie_t := 0.0          # son ollie'den beri (ollie'de hava pozu hemen gelir)
var _turn_blend := 0.0
var _hold_blend := 0.0
var _skel: Skeleton3D
var _hand_l := -1
var _tr: AnimationNodeTransition
var _face := 0.0             # 1 = gövde öne dönük (itme), 0 = yan duruş
var _face_hold := 0.0
var _tuck := 0.0
var _tuck_on := false
var _tuck_t := 0.0
var _grade_s := 0.0          # yumuşatılmış yokuş eğimi (tümsekler pozu bozmasın)
var _grind_slope := 0.0
var _ret_armed := false      # itme sürdü: bitince dönüş oynar
var _ret_t := 0.0
var _foot_jump_t := 99.0     # yaya zıplamasından beri
var _foot_land_t := 99.0     # yaya inişinden beri


## Eldeki eşyanın düğümü sol ele oturur (eşyanın kökü avucun biraz altında)
func _update_held_node() -> void:
	var n := controller.held_node
	if n == null or not is_instance_valid(n):
		return
	if _skel == null:
		_skel = _model.find_child("Skeleton3D", true, false)
		_hand_l = _skel.find_bone("hand.L")
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand_l).origin
	n.global_position = hand - Vector3.UP * 0.12
	n.global_basis = Basis(Vector3.UP, global_rotation.y)


func _ready() -> void:
	controller = get_parent() as SkateController
	# İniş çömelmesi yalnızca gerçek bir uçuştan sonra (tümsek/kenar titremesinde değil)
	controller.landed.connect(func(impact: float):
		if _air_t > 0.25 or impact > 2.0:
			_land_timer = 0.18)
	controller.ollied.connect(_on_ollied)
	# Kaldırım zıplaması: kısa ollie pozu ("pat" anından), yazı yok
	controller.auto_hopped.connect(func():
		_ollie_t = 0.0
		_start_special("ollie", OLLIE_POP_TIME))
	controller.stumbled.connect(_on_stumbled)
	controller.action_started.connect(func(n: String):
		_state = ""
		_set_state(n)
		_tree.set("parameters/%s_seek/seek_request" % n, 0.0))
	controller.knocked_down.connect(func():
		# Sarsılma üstüne binmiş olabilir: kesilir, yalnız düşme oynar
		_tree.set("parameters/sarsil_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_special = ""
		_state = ""
		var fall := "yaya_dus" if controller.fall_on_foot else "dus"
		_set_state(fall)
		_tree.set("parameters/%s_seek/seek_request" % fall, 0.0)
		_kick_arms(Vector2(-1.2, 1.6)))
	controller.ollie_started.connect(func(): _start_special("ollie", 0.0))
	controller.foot_jumped.connect(func():
		_foot_jump_t = 0.0
		_foot_land_t = 99.0
		_enter("yaya_zipla"))
	controller.landed.connect(func(_impact: float):
		if controller.on_foot and _air_t > 0.15:
			_foot_land_t = 0.0
			_enter("yaya_inis"))
	controller.double_jumped.connect(func():
		_start_special("flip", 0.0)
		_kick_arms(Vector2(0.2, 1.2)))
	_model = MODEL.instantiate()
	# Blender'da karakter -Y'ye bakıyor; glTF'te bu +Z olur. Oyunda ileri -Z.
	_model.rotation_degrees.y = 180.0
	add_child(_model)
	_convert_materials(_model)
	_setup_animation()
	_build_sparks()
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	_sway = ArmSway.new()
	skel.add_child(_sway)
	# Geçişlerde ayak tahtaya gömülmesin (en son çalışır)
	skel.add_child(FootGuard.new())
	# Müzik çalar, kulaklıklar ve kablo
	var mz := MuzikAksesuar.new()
	mz.controller = controller
	mz.model = _model
	add_child(mz)
	_prev_yaw = atan2(controller.heading.x, controller.heading.z)
	controller.ollied.connect(func(): _kick_arms(Vector2(0.0, 1.6)))
	controller.landed.connect(func(impact: float): _kick_arms(Vector2(-0.4, -0.5) * clampf(impact / 4.0, 0.0, 1.5)))


func _physics_process(delta: float) -> void:
	_time += delta
	_land_timer = maxf(_land_timer - delta, 0.0)
	if _special != "":
		_special_t += delta
		var landed_now := controller.grounded and not controller.is_winding_up() and _special_t > OLLIE_POP_TIME + 0.1
		if _special_t >= _special_len or controller.grinding or landed_now or controller.on_foot:
			_special = ""
	_ollie_t += delta
	_air_t = 0.0 if (controller.grounded or controller.grinding) else _air_t + delta
	_align(delta)
	# Bankta: görsel gövdeden oturağa kayar (gövde bankın önünde kalır)
	var sit_local := controller.global_basis.orthonormalized().inverse() * controller.sit_offset
	position = position.lerp(sit_local, 1.0 - exp(-9.0 * delta))
	_update_animation()
	_update_arm_sway(delta)
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
	elif controller.on_foot or controller.board_anim != SkateController.BoardAnim.NONE or controller.fall_time > 0.0:
		lean_target = 0.0
	else:
		# Dönüşe doğru eğil (hızla artar)
		var speed01 := clampf(absf(controller.speed) / 6.0, 0.0, 1.0)
		lean_target = -controller.steer * deg_to_rad(lean_angle) * speed01
	# Sarsılma: çarpmanın ilk anında kısa, hızla sönen sağa-sola sarsıntı
	if controller.stumble_time > 0.0:
		var k := clampf((controller.stumble_time - SkateController.STUMBLE_TIME * 0.6) / (SkateController.STUMBLE_TIME * 0.4), 0.0, 1.0)
		lean_target += sin(_time * 17.0) * 0.2 * k
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-10.0 * delta))
	target = target * Basis(Vector3(0, 0, 1), _lean)

	var current := global_basis.orthonormalized()
	global_basis = current.slerp(target, 1.0 - exp(-align_sharpness * delta))


# ---------- Animasyon ----------

func _setup_animation() -> void:
	_anim = _model.find_child("AnimationPlayer", true, false)
	for n in LOOPING:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_push_len = _anim.get_animation("push").length

	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = anim_blend
	_tr = tr
	for st in STATES:
		tr.add_input(st)
	bt.add_node("state", tr)

	var anim := func(name: String) -> AnimationNodeAnimation:
		var a := AnimationNodeAnimation.new()
		a.animation = name
		return a

	# Sürüş: hız (yavaş <-> hızlı) ve direksiyon (sol <- orta -> sağ) karışımı
	bt.add_node("a_ride_idle", anim.call("ride_idle"))
	bt.add_node("a_ride_fast", anim.call("ride_fast"))
	bt.add_node("a_turn_l", anim.call("ride_turn_l"))
	bt.add_node("a_turn_r", anim.call("ride_turn_r"))
	bt.add_node("ride_speed", AnimationNodeBlend2.new())
	bt.connect_node("ride_speed", 0, "a_ride_idle")
	bt.connect_node("ride_speed", 1, "a_ride_fast")
	bt.add_node("ride_turn", AnimationNodeBlend3.new())
	bt.connect_node("ride_turn", 0, "a_turn_l")
	bt.connect_node("ride_turn", 1, "ride_speed")
	bt.connect_node("ride_turn", 2, "a_turn_r")
	# Yüksek hız (tuck) ve itişler arası öne dönük duruş sürüşün üstüne karışır
	bt.add_node("a_tuck", anim.call("ride_tuck"))
	bt.add_node("tuck", AnimationNodeBlend2.new())
	bt.connect_node("tuck", 0, "ride_turn")
	bt.connect_node("tuck", 1, "a_tuck")
	bt.add_node("a_ready", anim.call("ride_ready"))
	bt.add_node("face", AnimationNodeBlend2.new())
	bt.connect_node("face", 0, "tuck")
	bt.connect_node("face", 1, "a_ready")
	bt.connect_node("state", STATES.find("ride"), "face")

	# Grind: düz ray <-> aşağı eğimli ray
	bt.add_node("a_grind", anim.call("grind"))
	bt.add_node("a_grind_down", anim.call("grind_down"))
	bt.add_node("grind_slope", AnimationNodeBlend2.new())
	bt.connect_node("grind_slope", 0, "a_grind")
	bt.connect_node("grind_slope", 1, "a_grind_down")
	bt.connect_node("state", STATES.find("grind"), "grind_slope")

	# İtme: hız 0, konum her karede parmaktan gelir
	bt.add_node("push_anim", anim.call("push"))
	bt.add_node("push_scale", AnimationNodeTimeScale.new())
	bt.add_node("push_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("push_scale", 0, "push_anim")
	bt.connect_node("push_seek", 0, "push_scale")
	bt.connect_node("state", STATES.find("push"), "push_seek")

	# Yürüme / koşu: hız gerçek harekete göre ölçeklenir
	for st in ["walk", "run"]:
		bt.add_node(st + "_anim", anim.call(st))
		bt.add_node(st + "_scale", AnimationNodeTimeScale.new())
		bt.connect_node(st + "_scale", 0, st + "_anim")
		bt.connect_node("state", STATES.find(st), st + "_scale")

	# Zıplamalar: bir noktadan başlatılabilir (rampadan / raydan çıkışta "pat" anından)
	for st in ["ollie", "flip", "push_ret", "yaya_zipla", "yaya_inis", "dus", "yaya_dus", "cantaya_at", "canta_ac", "canta_kapat", "eline_al", "cantaya_koy", "muzik_cikar", "muzik_koy", "muzik_cikar_kisa", "muzik_kulaklik_cikar"]:
		bt.add_node(st + "_anim", anim.call(st))
		bt.add_node(st + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(st + "_seek", 0, st + "_anim")
		bt.connect_node("state", STATES.find(st), st + "_seek")

	for st in ["brake", "crouch", "air", "stand_idle", "mount", "dismount", "tutun", "yaya_hava", "canta_acik", "havada_cirpin", "otur", "muzik_bak"]:
		bt.add_node(st, anim.call(st))
		bt.connect_node("state", STATES.find(st), st)

	# Sarsılma: o an oynayan her şeyin üstüne tek seferlik biner (ayak yere, geri biniş)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.06
	shot.fadeout_time = 0.18
	bt.add_node("sarsil_shot", shot)
	bt.add_node("sarsil_anim", anim.call("sarsil"))
	# Elde eşya: sol kol "elde_tut" pozunda (yürürken de); yalnız sol kol kemikleri karışır
	var hold := AnimationNodeBlend2.new()
	hold.filter_enabled = true
	for path in _bone_track_paths(["upper_arm.L", "forearm.L", "hand.L"]):
		hold.set_filter_path(path, true)
	bt.add_node("hold", hold)
	bt.add_node("hold_anim", anim.call("elde_tut"))
	bt.connect_node("hold", 0, "state")
	bt.connect_node("hold", 1, "hold_anim")
	bt.connect_node("sarsil_shot", 0, "hold")
	bt.connect_node("sarsil_shot", 1, "sarsil_anim")
	bt.connect_node("output", 0, "sarsil_shot")

	_tree = AnimationTree.new()
	_tree.tree_root = bt
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.set("parameters/push_scale/scale", 0.0)
	_tree.active = true
	_set_state("ride")


## Kemik iz yolları (AnimationTree filtresi için): "walk" animasyonundaki izlerden
func _bone_track_paths(bones: Array) -> Array:
	var out := []
	var a := _anim.get_animation("walk")
	for i in a.get_track_count():
		var path := a.track_get_path(i)
		var sub := String(path.get_concatenated_subnames())
		if sub in bones and not out.has(path):
			out.append(path)
	return out


## Tek seferlik bir duruma baştan gir
func _enter(st: String) -> void:
	_set_state(st)
	_tree.set("parameters/%s_seek/seek_request" % st, 0.0)


func _set_state(st: String) -> void:
	if st == _state:
		return
	# Geçiş süresi: dönüş hareketi itişler arası duruşla aynı karede biter (kısa);
	# frene girip çıkarken gövde dönüyor (uzun)
	var xf := anim_blend
	if _state == "push_ret" and st == "ride":
		xf = 0.08
	elif st == "brake" or _state == "brake":
		xf = 0.28
	elif _state == "push" and st == "push_ret":
		xf = 0.1
	_tr.xfade_time = xf
	_state = st
	_tree.set("parameters/state/transition_request", st)


func _update_animation() -> void:
	var inp := SkateInput
	var dt := get_physics_process_delta_time()
	var st := "ride"
	var push_t := -1.0

	if controller.held_in_air:
		st = "havada_cirpin"
	elif controller.fall_time > 0.0:
		st = "yaya_dus" if controller.fall_on_foot else "dus"
	elif controller.sitting:
		st = "otur"
	elif controller.action_time > 0.0 and controller.action_name != "":
		st = controller.action_name
	elif controller.bag_open and controller.on_foot:
		st = "canta_acik"
	elif controller.music_open and controller.on_foot:
		st = "muzik_bak"
	elif controller.skitch_car:
		st = "tutun"
	elif controller.board_anim == SkateController.BoardAnim.MOUNTING:
		st = "mount"
	elif controller.board_anim == SkateController.BoardAnim.DISMOUNTING:
		st = "dismount"
	elif controller.on_foot:
		var v := controller.speed
		_foot_jump_t += dt
		_foot_land_t += dt
		if not controller.grounded and _foot_jump_t < YAYA_ZIPLA_TIME:
			st = "yaya_zipla"
		elif not controller.grounded and _air_t > 0.06:
			st = "yaya_hava"
		elif _foot_land_t < (YAYA_INIS_TIME if v < 2.6 else YAYA_INIS_TIME * 0.5):
			st = "yaya_inis"
		elif v > 2.6:
			st = "run"
			_tree.set("parameters/run_scale/scale", clampf(v / run_anim_speed, 0.6, 2.5))
		elif v > 0.15:
			st = "walk"
			_tree.set("parameters/walk_scale/scale", clampf(v / walk_anim_speed, 0.4, 2.5))
		else:
			st = "stand_idle"
	elif controller.grinding:
		st = "grind"
	elif _special != "":
		st = _special
	elif not controller.grounded and (_air_t > 0.12 or _ollie_t < 0.3):
		# Kısa kopmalarda (tümsek, kenar) hava pozuna geçme: titremeyi önler
		st = "air"
	elif _land_timer > 0.0:
		st = "crouch"
	elif inp.gesture == SkateInput.Gesture.PUSH and inp.foot_contact:
		st = "push"
		push_t = inp.push_progress
	elif inp.gesture == SkateInput.Gesture.REVERSE and inp.foot_contact:
		# Geri itme: ayak arkadan öne sürtülür, aynı animasyon tersine
		st = "push"
		push_t = 1.0 - inp.push_progress
	elif inp.gesture == SkateInput.Gesture.BRAKE:
		st = "brake"
	# İtme bitince ayak bir kez kaykaya geri biner (yeni itme ya da başka durum keser)
	if st == "push" and inp.gesture == SkateInput.Gesture.PUSH:
		_ret_armed = true
	elif _ret_armed and st == "ride":
		if _state != "push_ret":
			_ret_t = 0.0
			_set_state("push_ret")
			_tree.set("parameters/push_ret_seek/seek_request", 0.0)
		_ret_t += dt
		if _ret_t < PUSH_RET_TIME:
			st = "push_ret"
		else:
			_ret_armed = false
	elif st != "push":
		_ret_armed = false
	_set_state(st)
	if push_t >= 0.0:
		_tree.set("parameters/push_seek/seek_request", push_t * _push_len)

	# Sürüş karışımı: hız ve direksiyona yumuşakça tepki
	var speed01 := clampf(absf(controller.speed) / fast_ride_speed, 0.0, 1.0)
	_speed_blend = lerpf(_speed_blend, speed01, 1.0 - exp(-4.0 * dt))
	var turn := controller.steer * clampf(absf(controller.speed) / 3.0, 0.0, 1.0)
	_turn_blend = lerpf(_turn_blend, turn, 1.0 - exp(-8.0 * dt))
	_tree.set("parameters/ride_speed/blend_amount", _speed_blend)
	# Elde eşya: sol kol tutuş pozunda (alma / koyma / düşme sırasında kapalı)
	var want_hold := 1.0 if controller.held_item != "" and controller.on_foot and controller.action_time <= 0.0 \
		and controller.fall_time <= 0.0 and not controller.held_in_air else 0.0
	_hold_blend = lerpf(_hold_blend, want_hold, 1.0 - exp(-12.0 * dt))
	_tree.set("parameters/hold/blend_amount", _hold_blend)
	_update_held_node()
	_tree.set("parameters/ride_turn/blend_amount", _turn_blend)
	_update_stance(st, dt)


## Yan duruş / öne dönük duruş, yüksek hız ve grind eğimi karışımları
func _update_stance(st: String, dt: float) -> void:
	var inp := SkateInput
	var pushing := st == "push" or st == "push_ret" or st == "mount" or st == "brake" \
		or (inp.gesture == SkateInput.Gesture.PUSH and not controller.on_foot)
	if pushing:
		_face_hold = push_face_hold
	else:
		_face_hold = maxf(_face_hold - dt, 0.0)
	var want_face := 1.0 if _face_hold > 0.0 else 0.0
	_face = move_toward(_face, want_face, (face_in_rate if want_face > _face else face_out_rate) * dt)
	# Yumuşak başlangıç / bitiş (gövde dönüşü sarsılmasın)
	_tree.set("parameters/face/blend_amount", _face * _face * (3.0 - 2.0 * _face))

	var kmh := absf(controller.speed) * 3.6
	var grade := -controller.forward_on_ground.normalized().y * signf(controller.speed)
	if controller.grounded:
		_grade_s = lerpf(_grade_s, grade, 1.0 - exp(-3.0 * dt))
	grade = _grade_s
	# Arazideki tümseklerde kısa havalanmalar sayılmaz
	var riding := not controller.on_foot and not controller.grinding and (controller.grounded or _air_t < 0.35)
	if _tuck_on:
		if not riding or kmh < tuck_exit_kmh or grade < tuck_exit_grade or _face > 0.5:
			_tuck_on = false
	if not _tuck_on:
		if riding and kmh > tuck_kmh and grade > tuck_grade and _face < 0.5:
			_tuck_t += dt
			if _tuck_t >= tuck_delay:
				_tuck_on = true
		else:
			_tuck_t = 0.0
	# Havada kısa kopmalar (tümsek) tuck'u bozmasın: yalnız yerde değişir
	if controller.grounded or controller.grinding or not _tuck_on:
		_tuck = move_toward(_tuck, 1.0 if _tuck_on else 0.0, 2.2 * dt)
	_tree.set("parameters/tuck/blend_amount", _tuck * _tuck * (3.0 - 2.0 * _tuck))

	if controller.grinding:
		var g := clampf(-controller.grind_dir.normalized().y / maxf(grind_down_grade, 0.01), 0.0, 1.0)
		_grind_slope = lerpf(_grind_slope, g, 1.0 - exp(-8.0 * dt))
	_tree.set("parameters/grind_slope/blend_amount", _grind_slope)


func _on_stumbled() -> void:
	_kick_arms(Vector2(-0.7, 1.4))
	_tree.set("parameters/sarsil_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# ---------- Zıplamalar ----------

func _start_special(name: String, from_time: float) -> void:
	_special = name
	_special_t = from_time
	_special_len = _anim.get_animation(name).length
	_state = ""   # aynı duruma tekrar geçişte de baştan başlasın
	_set_state(name)
	_tree.set("parameters/%s_seek/seek_request" % name, from_time)


## Fiziksel sıçrama oldu. Hazırlıklı ollie zaten oynuyor; raydan / kenardan
## ani zıplamada animasyonu "pat" anından başlat.
func _on_ollied() -> void:
	_ollie_t = 0.0
	if _special != "ollie":
		_start_special("ollie", OLLIE_POP_TIME)


# ---------- Kol sallanması (fizik) ----------

## Kollara ani bir itki ver (ollie, iniş).
func _kick_arms(impulse: Vector2) -> void:
	for side in ["L", "R"]:
		_sway_vel[side] += impulse


## Kollar bir yay gibi: hedef açı ortam koşullarından gelir, kollar ona sönümlü
## salınımla yaklaşır. Böylece kas gücüyle değil, hız ve hareketle sallanırlar.
func _update_arm_sway(delta: float) -> void:
	if delta <= 0.0:
		return
	var speed := absf(controller.speed)
	var accel := (controller.speed - _prev_speed) / delta
	_prev_speed = controller.speed
	var yaw := atan2(controller.heading.x, controller.heading.z)
	var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	# Sağa dönüşte (yaw azalır) merkezkaç kolları sola iter
	var centrifugal := speed * -yaw_rate

	var on_foot := controller.on_foot
	var wind := sway_wind * speed * (0.4 if on_foot else 1.0)
	var inertia := clampf(accel, -12.0, 12.0) * sway_inertia
	var step := 0.0
	if on_foot and speed > 0.2:
		_step_phase += delta * speed * 2.6
		step = sin(_step_phase) * sway_step * clampf(speed / 2.0, 0.0, 1.0)
	var air := 0.0
	if not controller.grounded and not controller.grinding and not on_foot:
		air = clampf(-controller.velocity.y * 0.04, -0.15, 0.25)   # düşerken kollar hafif kalkar

	for side in ["L", "R"]:
		var s := 1.0 if side == "L" else -1.0
		var target := Vector2(
			wind + inertia + step * s,
			air + clampf(centrifugal * sway_turn * s, -0.35, 0.35))
		var pos: Vector2 = _sway_pos[side]
		var vel: Vector2 = _sway_vel[side]
		vel += ((target - pos) * sway_stiffness - vel * sway_damping) * delta
		pos += vel * delta
		pos = pos.clamp(Vector2(-sway_max, -0.2), Vector2(sway_max, sway_max))
		_sway_pos[side] = pos
		_sway_vel[side] = vel

	# Binme / inmede kaykayı tutan kol animasyona sadık kalsın
	var weight := 0.25 if controller.board_anim != SkateController.BoardAnim.NONE else 1.0
	_sway.left = _sway_pos["L"] * weight
	_sway.right = _sway_pos["R"] * weight


# ---------- Malzemeler ----------

## İçe aktarılan düz renkli malzemeleri oyunun ortak shader'ına çevirir
## (toon ışık, poligon titremesi vb. görünüm ayarları karaktere de uygulansın).
func _convert_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var color := Color.WHITE
			if src is BaseMaterial3D:
				color = src.albedo_color
			var m := ShaderMaterial.new()
			m.shader = CHAR_SHADER
			m.set_shader_parameter("albedo", color)
			node.set_surface_override_material(i, m)
	for child in node.get_children():
		_convert_materials(child)


# ---------- Grind kıvılcımları ----------

func _build_sparks() -> void:
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


func _update_sparks() -> void:
	_sparks.emitting = controller.grinding
	if controller.grinding:
		var back := -controller.grind_dir
		if absf(back.y) < 0.99:
			_sparks.global_basis = Basis.looking_at(back, Vector3.UP)
