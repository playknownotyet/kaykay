class_name SkateController
extends CharacterBody3D
## Arcade kaykay kontrolcüsü.
##
## Temel fikir: kaykay yana kaymaz (tekerlekler yana tutar), sadece baktığı
## yöne doğru yuvarlanır. Bu yüzden hızı tek bir sayı (`speed`) olarak tutup
## her karede hızı zemin düzlemine izdüşürülmüş ileri yöne uyguluyoruz.
## Bu "raydaymış gibi akan" kaykay hissinin sırrı.

signal landed(impact: float)
signal ollied
signal grind_started
signal grind_ended

# --- Ayar panelinden değiştirilebilen değerler ---
@export var gravity := 15.0
## Düz zeminde kendiliğinden yavaşlama (m/sn²).
@export var rolling_resistance := 0.22
## Hızın karesiyle artan hava direnci; azami hızı yumuşakça sınırlar.
@export var air_drag := 0.012
## Ayak yere bastığında hızın ayak hızına ne kadar çabuk yaklaştığı.
@export var push_grip := 4.0
@export var brake_strength := 7.0
## Ayakla geri itmenin verimi (1 = ileri itme kadar kolay). Düşük = daha çok efor.
@export var reverse_efficiency := 0.55
@export var reverse_max_speed := 3.0
@export var max_speed := 16.0
## Hızlıyken en dar dönüş yarıçapı (metre).
@export var turn_radius := 2.8
## Dururken / çok yavaşken dönüş hızı (rad/sn).
@export var min_turn_rate := 1.4
@export var max_turn_rate := 2.6
## Butonla direksiyonda dönüşün tam güce çıkma hızı (1/sn).
@export var steer_response := 4.0
@export var steer_return := 8.0
@export var ollie_speed := 4.2
@export var air_steer_rate := 2.0
## Duvara sürterken kaybedilen hız oranı.
@export var wall_speed_loss := 0.5
@export var floor_snap := 0.35

# --- Grind ---
## Havadayken raya bu kadar yatay yakınlıkta (m) kendiliğinden tutunur.
@export var grind_latch_radius := 0.6
## Yaklaşma açısı bundan büyükse (raya fazla dik) tutunmaz.
@export var grind_max_angle := 70.0
## Bu açının altında 50-50, üstünde boardslide.
@export var boardslide_angle := 35.0
@export var grind_friction := 0.5
## Raya tutununca en az bu hızla kayar (m/sn); yavaş girişler de akıcı olsun.
@export var grind_min_speed := 3.0
## Rayın sonunda kendiliğinden çıkarken hafif yukarı sıçrama.
@export var grind_exit_pop := 1.5
## Raydan ollie ile çıkarken joystick ile yana itme.
@export var grind_side_jump := 2.5

# --- Durum (görsel ve kamera okur) ---
var speed := 0.0
var heading := Vector3.FORWARD      # yatay birim vektör (dünya)
var steer := 0.0                    # yumuşatılmış direksiyon, -1..1
var grounded := true
var ground_normal := Vector3.UP
var forward_on_ground := Vector3.FORWARD
var air_time := 0.0
var grinding := false
var grind_style := 0                # 0 = 50-50 (ray boyunca), 1 = boardslide (dik)
var grind_time := 0.0
var grind_dir := Vector3.FORWARD    # 3D gidiş yönü (eğimli raylarda eğik)

var _coyote := 0.0
var _ollie_buffer := 0.0
var _ollie_lock := 0.0
var _spawn := Transform3D.IDENTITY
var _rail: GrindRail
var _rail_pos := 0.0                # rayın a ucundan uzaklık (m)
var _rail_sign := 1.0
var _snap_offset := Vector3.ZERO
var _last_rail: GrindRail
var _last_rail_timer := 0.0

const COYOTE_TIME := 0.1
const OLLIE_BUFFER_TIME := 0.12


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.25
	shape.height = 1.5
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.75
	add_child(col)

	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = floor_snap
	floor_stop_on_slope = false
	_spawn = global_transform
	heading = -global_basis.z
	heading.y = 0.0
	heading = heading.normalized()


func respawn() -> void:
	cancel_grind()
	global_transform = _spawn
	heading = Vector3.FORWARD
	speed = 0.0
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var inp := SkateInput
	_update_steer(inp, delta)

	if inp.consume_ollie():
		_ollie_buffer = OLLIE_BUFFER_TIME
	_ollie_buffer = maxf(_ollie_buffer - delta, 0.0)
	_coyote = maxf(_coyote - delta, 0.0)
	_ollie_lock = maxf(_ollie_lock - delta, 0.0)
	_last_rail_timer = maxf(_last_rail_timer - delta, 0.0)

	if grinding:
		_grind_move(delta)
		return

	if grounded:
		_ground_move(inp, delta)
	else:
		_air_move(delta)

	if _ollie_buffer > 0.0 and (grounded or _coyote > 0.0):
		_do_ollie()

	floor_snap_length = 0.0 if _ollie_lock > 0.0 else floor_snap
	var pre_velocity := velocity
	move_and_slide()
	_after_move(pre_velocity)

	if not grounded:
		_try_latch()

	if global_position.y < -10.0:
		respawn()


func _update_steer(inp: Node, delta: float) -> void:
	var target: float = inp.steer_target
	if inp.steer_is_digital:
		if target == 0.0:
			steer = move_toward(steer, 0.0, steer_return * delta)
		else:
			# Ters yöne basılırsa önce hızlıca sıfıra döner
			var rate := steer_return if signf(target) != signf(steer) and steer != 0.0 else steer_response
			steer = move_toward(steer, target, rate * delta)
	else:
		steer = lerpf(steer, target, 1.0 - exp(-15.0 * delta))


func _ground_move(inp: Node, delta: float) -> void:
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	ground_normal = n
	var fwd := _project_on_plane(heading, n)
	var g := Vector3.DOWN * gravity
	var g_on_plane := g - n * g.dot(n)

	# Eğimde yerçekimi hızlandırır / yavaşlatır
	speed += g_on_plane.dot(fwd) * delta

	# İtme: ayak, kaykaydan daha hızlı geriye gidiyorsa hızlandırır.
	# Böylece yavaş sürtmek yüksek hızda işe yaramaz, hızlı sürtmek yarar.
	if inp.foot_contact:
		if inp.gesture == SkateInput.Gesture.PUSH:
			speed += push_grip * maxf(inp.foot_speed - speed, 0.0) * delta
		elif inp.gesture == SkateInput.Gesture.REVERSE:
			# Ayak ileri doğru iter, kaykay geri gider. Verim düşük: daha çok efor.
			var rev_foot := minf(inp.foot_speed * reverse_efficiency, reverse_max_speed)
			speed -= push_grip * maxf(rev_foot + speed, 0.0) * delta

	if inp.brake > 0.0:
		speed = move_toward(speed, 0.0, brake_strength * inp.brake * delta)

	speed = move_toward(speed, 0.0, (rolling_resistance + air_drag * speed * speed) * delta)
	speed = clampf(speed, -max_speed * 0.5, max_speed)

	# Direksiyon: hızlıyken sabit yarıçap, yavaşken en az belli bir dönüş hızı
	var turn_rate := clampf(absf(speed) / turn_radius, min_turn_rate, max_turn_rate)
	heading = heading.rotated(Vector3.UP, -steer * turn_rate * delta)

	# Yan eğimde (bank) yerçekimi kaykayı aşağı doğru kıvırır
	var lateral := g_on_plane - fwd * g_on_plane.dot(fwd)
	if lateral.length() > 0.05 and absf(speed) > 0.5:
		var lat_h := Vector3(lateral.x, 0.0, lateral.z)
		var side := signf(heading.cross(lat_h).y)
		var carve := minf(lateral.length() / maxf(absf(speed), 2.0), 2.0)
		heading = heading.rotated(Vector3.UP, side * carve * delta)

	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	fwd = _project_on_plane(heading, n)
	forward_on_ground = fwd
	velocity = fwd * speed
	inp.board_speed = speed


func _air_move(delta: float) -> void:
	air_time += delta
	velocity.y -= gravity * delta
	heading = heading.rotated(Vector3.UP, -steer * air_steer_rate * delta)
	ground_normal = ground_normal.slerp(Vector3.UP, 1.0 - exp(-4.0 * delta))
	forward_on_ground = heading


func _do_ollie() -> void:
	_ollie_buffer = 0.0
	_coyote = 0.0
	_ollie_lock = 0.15
	velocity += Vector3.UP * ollie_speed
	grounded = false
	air_time = 0.0
	ollied.emit()


func _after_move(pre_velocity: Vector3) -> void:
	var was_grounded := grounded
	grounded = is_on_floor() and _ollie_lock <= 0.0

	if grounded and not was_grounded:
		var n := get_floor_normal()
		var fwd := _project_on_plane(heading, n)
		var impact := maxf(-pre_velocity.dot(n), 0.0)
		speed = pre_velocity.dot(fwd)
		ground_normal = n
		air_time = 0.0
		landed.emit(impact)
	elif was_grounded and not grounded and _ollie_lock <= 0.0:
		# Rampadan uçtu veya kenardan düştü: kısa süre yine ollie yapılabilir
		_coyote = COYOTE_TIME
		air_time = 0.0

	_handle_walls()


func _handle_walls() -> void:
	var worst := Vector3.ZERO
	var worst_into := 0.0
	var wall_dot := cos(floor_max_angle)
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y >= wall_dot or n.y < -0.5:
			continue
		var nh := Vector3(n.x, 0.0, n.z).normalized()
		var into := -heading.dot(nh) * signf(speed if grounded else 1.0)
		if into > worst_into:
			worst_into = into
			worst = nh
	if worst_into <= 0.0:
		return
	if worst_into > 0.85:
		# Kafa kafaya çarpma: hafif geri sekme
		speed = -speed * 0.15
		velocity = Vector3(velocity.x * -0.15, velocity.y, velocity.z * -0.15)
	else:
		# Sıyırma: duvara paralel yöne dön, biraz hız kaybet
		heading = (heading - worst * heading.dot(worst)).normalized()
		speed *= 1.0 - worst_into * wall_speed_loss


# ---------- Grind ----------

func _try_latch() -> void:
	var p := global_position
	var vh := Vector3(velocity.x, 0.0, velocity.z)
	var move_dir := vh.normalized() if vh.length() > 0.5 else heading
	var min_align := cos(deg_to_rad(grind_max_angle))
	var best: GrindRail
	var best_s := 0.0
	var best_dist := INF
	var best_align := 0.0
	for node in get_tree().get_nodes_in_group("grind_rails"):
		var rail := node as GrindRail
		if rail == _last_rail and _last_rail_timer > 0.0:
			continue
		var s := rail.closest_s(p)
		if s <= 0.05 or s >= rail.length - 0.05:
			continue
		var c := rail.point_at(s)
		var dy := p.y - c.y
		if dy < -0.25 or dy > 0.7:
			continue
		var dist := Vector2(p.x - c.x, p.z - c.z).length()
		if dist > grind_latch_radius or dist >= best_dist:
			continue
		var dh := Vector3(rail.direction.x, 0.0, rail.direction.z).normalized()
		var align := move_dir.dot(dh)
		if absf(align) < min_align:
			continue
		best = rail
		best_s = s
		best_dist = dist
		best_align = align
	if best:
		_start_grind(best, best_s, best_align, vh.length())


func _start_grind(rail: GrindRail, s: float, align: float, h_speed: float) -> void:
	_rail = rail
	_rail_pos = s
	_rail_sign = 1.0 if align >= 0.0 else -1.0
	grind_style = 0 if absf(align) >= cos(deg_to_rad(boardslide_angle)) else 1
	# Çapraz girişte hızın bir kısmı kaybolur ama asla çok yavaş kalmaz
	speed = maxf(h_speed * lerpf(0.7, 1.0, absf(align)), grind_min_speed)
	_snap_offset = global_position - rail.point_at(s)
	grinding = true
	grounded = false
	grind_time = 0.0
	air_time = 0.0
	grind_started.emit()


func _grind_move(delta: float) -> void:
	var d := _rail.direction * _rail_sign
	grind_dir = d
	speed += -gravity * d.y * delta
	speed = move_toward(speed, 0.0, grind_friction * delta)
	speed = minf(speed, max_speed)
	_rail_pos += speed * _rail_sign * delta
	grind_time += delta

	# Raya yumuşakça otur (ani ışınlanma görünmesin)
	_snap_offset = _snap_offset.lerp(Vector3.ZERO, 1.0 - exp(-25.0 * delta))
	global_position = _rail.point_at(clampf(_rail_pos, 0.0, _rail.length)) + _snap_offset

	var dh := Vector3(d.x, 0.0, d.z)
	if dh.length() > 0.01:
		heading = dh.normalized()
	forward_on_ground = d
	ground_normal = (Vector3.UP - d * d.y).normalized()   # eğimli rayda kaykay da eğilir
	velocity = d * speed

	if _ollie_buffer > 0.0:
		_exit_grind(true)
	elif _rail_pos <= 0.0 or _rail_pos >= _rail.length or speed < 0.3:
		_exit_grind(false)

	if global_position.y < -10.0:
		respawn()


func _exit_grind(jump: bool) -> void:
	grinding = false
	var d := _rail.direction * _rail_sign
	velocity = d * speed + Vector3.UP * (ollie_speed if jump else grind_exit_pop)
	# Joystick yana basılıysa raydan yana atla ve bu raya bir süre tutunma;
	# basılı değilse sadece zıpla, aynı raya geri konabilirsin (hop).
	var hand: float = SkateInput.steer_target
	var transfer := jump and absf(hand) > 0.3
	if jump:
		if transfer:
			var side := d.cross(Vector3.UP).normalized()
			velocity += side * signf(hand) * grind_side_jump
		_ollie_buffer = 0.0
		ollied.emit()
	global_position += Vector3.UP * 0.03
	grounded = false
	_ollie_lock = 0.15
	air_time = 0.0
	_last_rail = _rail
	_last_rail_timer = 1.0 if transfer else 0.25
	_rail = null
	grind_ended.emit()


## Grind'i hemen bırakır (ışınlanma / yeniden doğma için).
func cancel_grind() -> void:
	if grinding:
		grinding = false
		_rail = null
		grind_ended.emit()


static func _project_on_plane(v: Vector3, n: Vector3) -> Vector3:
	var p := v - n * v.dot(n)
	if p.length_squared() < 0.0001:
		return v
	return p.normalized()
