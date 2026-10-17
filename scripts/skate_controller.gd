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
signal ollie_started      # çökme (hazırlık) başladı; asıl sıçrama ollie_windup sonra
signal double_jumped
signal wall_hit(strength: float)   # duvara / bordüre çarpma (m/sn cinsinden şiddet)
signal stumbled                     # sert çarpma: karakter sarsılır, ayağını yere koyup geri biner
signal grind_started
signal grind_ended
signal mode_changed(on_foot: bool)
signal knocked_down                 # araba çarptı: düşer, kalkar, kendiliğinden kaykaya biner
signal skitch_changed(on: bool)     # arabanın arkasına tutundu / bıraktı
signal action_started(name: String) # tek seferlik eylem (çantaya atma vb.)
signal context_action(id: String)   # bağlam butonu (soygun başlat, al ...) basıldı
signal auto_hopped                  # kaldırım önünde kendiliğinden küçük zıplama
signal inventory_changed
signal sat_down
signal stood_up
signal bag_changed(open: bool)
signal stow_started(item: String)   # elindeki eşyayı çantaya atmaya başladı
signal item_stowed(item: String)    # eşya çantada

# --- Ayar panelinden değiştirilebilen değerler ---
@export var gravity := 14.5
## Düz zeminde kendiliğinden yavaşlama (m/sn²).
@export var rolling_resistance := 0.09
## Hızın karesiyle artan hava direnci; azami hızı yumuşakça sınırlar.
@export var air_drag := 0.0045
## İtme gücü (m/sn²): ayak yere bastığı sürece verdiği ivme. Kaykay ayak hızına
## push_taper (m/sn) kadar yaklaşınca azalır, ayak hızında biter.
@export var push_grip := 14.0
@export var push_taper := 2.0
@export var brake_strength := 6.8
## Atalet: ivme (itme, yokuş) ve yavaşlama (sürtünme, fren) hıza birden değil, bu tepki
## hızıyla (1/sn) yumuşakça biner. Düşük = daha ağır, kütleli; hız değişimi ivmeli artar / azalır.
@export var drive_response := 5.0
@export var resist_response := 2.5
## Yokuş aşağı itmede ayak hızına eklenen pay: eğim ivmesi (m/sn²) başına m/sn, en çok
@export var downhill_push_gain := 1.3
@export var downhill_push_max := 4.5
## Ayakla geri itmenin verimi (1 = ileri itme kadar kolay). Düşük = daha çok efor.
@export var reverse_efficiency := 0.5
@export var reverse_max_speed := 2.9
@export var max_speed := 16.0
## Hızlıyken en dar dönüş yarıçapı (metre).
@export var turn_radius := 2.5
## Dururken / çok yavaşken dönüş hızı (rad/sn).
@export var min_turn_rate := 1.35
@export var max_turn_rate := 2.5
## Butonla direksiyonda dönüşün tam güce çıkma hızı (1/sn).
@export var steer_response := 3.5
@export var steer_return := 7.5
@export var ollie_speed := 4.2
## Ollie öncesi dizlerin çöktüğü süre (sn); animasyondaki OLLIE_POP_FRAME ile aynı
@export var ollie_windup := 0.1
## Havada ikinci zıplama: normal ollie yüksekliğinin bu katı
@export var double_jump_height := 1.3
@export var air_steer_rate := 2.0
## Duvara sürterken kaybedilen hız oranı.
@export var wall_speed_loss := 0.5
## Sarsılma (ayak yere basıp geri biniş) eşikleri, km/s: canlıya ve sabit nesneye çarpma
@export var stumble_creature_kmh := 15.0
@export var stumble_wall_kmh := 25.0
## Sarsılmada ayak yerdeyken kaykayın yavaşlaması (m/sn²)
@export var stumble_brake := 6.0
@export var floor_snap := 0.35
## Yerdeyken zemine bastırma hızı (m/sn); ileri hıza etkisi yok.
@export var ground_stick := 1.0

# --- Kesintisiz sürüş ---
## Kaldırım gibi alçak basamakların önünde kendiliğinden küçük zıplama (hız kaybı yok)
@export var auto_hop := true
## Bu yüksekliğe (m) kadar basamaklar otomatik aşılır (zıplayarak ya da adım atarak)
@export var step_max := 0.32
## Zıplamanın basamağın ne kadar üstünden geçeceği (m)
@export var auto_hop_clear := 0.1

# --- Yaya ---
@export var walk_speed := 1.8
@export var run_speed := 4.0
@export var walk_accel := 10.0
@export var walk_turn_rate := 10.0
## Yayayken zıplama hızı (m/sn): 4.4 -> ~0,67 m
@export var foot_jump_speed := 4.4
signal foot_jumped

# Binme / inme animasyonlarıyla aynı süre ve hız (tools/blender/karakter_rig.py)
## Binme: kaykayı yere bırakıp üstüne basar ve bir kez iter (karakter_rig.py MOUNT_FRAMES / 30)
const MOUNT_TIME := 0.8
const MOUNT_SPEED := 2.2
const DISMOUNT_TIME := 0.5
enum BoardAnim { NONE, MOUNTING, DISMOUNTING }

# --- Grind ---
## Havadayken raya bu kadar yatay yakınlıkta (m) kendiliğinden tutunur.
@export var grind_latch_radius := 0.55
## Yaklaşma açısı bundan büyükse (raya fazla dik) tutunmaz.
@export var grind_max_angle := 69.0
## Bu açının altında 50-50, üstünde boardslide.
@export var boardslide_angle := 36.0
@export var grind_friction := 0.55
## Raya tutununca en az bu hızla kayar (m/sn); yavaş girişler de akıcı olsun.
@export var grind_min_speed := 3.0
## Rayın sonunda kendiliğinden çıkarken hafif yukarı sıçrama.
@export var grind_exit_pop := 1.4
## Raydan zıplayınca yana itme (joystick hangi yöndeyse oraya; boştaysa raya gelinen yana).
@export var grind_side_jump := 3.2
## Raydan zıplayınca bu süre hiçbir raya tutunulmaz (yan parçalara geri yapışmasın).
@export var grind_exit_block := 0.45

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
var on_foot := false                # kaykaydan inmiş, yürüyor
var floor_surface := "asfalt"       # üstünde olunan yüzey türü (level_builder "surface" bilgisi)
var stumble_time := 0.0             # > 0: sarsılma sürüyor (animasyon "sarsil", 24 kare)
const STUMBLE_TIME := 0.8
## Sarsılma animasyonunda sol ayağın yerde olduğu aralık (sn, başlangıçtan): kaykay sürtünüp yavaşlar
const STUMBLE_FOOT_DOWN := Vector2(0.2, 0.52)
var board_anim: int = BoardAnim.NONE  # binme / inme sürüyor mu
var board_anim_time := 0.0
## > 0: araba çarpmış, yerde (animasyon "dus", 66 kare). Bu sürede kontrol yok.
var fall_time := 0.0
const FALL_TIME := 2.2
## Yayayken çarpılınca: kaykay elde düşer, kalkıp yaya devam eder ("yaya_dus", 45 kare)
const FOOT_FALL_TIME := 1.5
var fall_on_foot := false
## Tutunma: trafik yöneticisi yakındaki uygun arabayı yazar; tutununca skitch_car olur
var skitch_candidate: Araba = null
var skitch_car: Araba = null
## Tek seferlik eylem (animasyon adı) ve kalan süresi: bu sürede hareket yok
var action_name := ""
var action_time := 0.0
## Girdiler kilitli (soygunda kuş bakışı keşif): yürüme / zıplama / binme yok
var input_locked := false
## Ekranda gösterilecek bağlam butonları: [{id, icon}] (dükkan vb. her kare yazar)
var context_buttons: Array = []

# --- Envanter: sırt çantası (4 göz) ve elde tutulan eşya ---
var inventory: Array = ["", "", "", ""]
var held_item := ""
## Elde tutulan eşyanın düğümü (görsel her kare sol ele oturtur)
var held_node: Node3D = null
var bag_open := false
## Bankta oturuyor: gövde bankın önünde durur, görsel sit_offset kadar kayıp oturağa yerleşir
var sitting := false
var sit_offset := Vector3.ZERO
var _sit_t := 0.0
## Sinematik: biri tutup taşıyor (konumu dışarıdan verilir, fizik yok)
var held_in_air := false
## karakter_rig.py: canta_ac / canta_kapat 24 kare, cantaya_koy 24 kare (14. karede çantada)
const BAG_ANIM_TIME := 24.0 / 30.0
const STOW_TIME := 24.0 / 30.0
const STOW_DROP := 14.0 / 30.0
var _stow_t := -1.0

var _coyote := 0.0
var _drive_acc := 0.0           # o anki itici ivme (m/sn²): itme + yokuş, yumuşatılmış
var _resist_acc := 0.0          # o anki yavaşlatıcı ivme: sürtünme + fren, yumuşatılmış
var _ollie_buffer := 0.0
var _ollie_lock := 0.0
var _spawn := Transform3D.IDENTITY
var _rail: GrindRail
var _rail_pos := 0.0                # rayın a ucundan uzaklık (m)
var _rail_sign := 1.0
var _snap_offset := Vector3.ZERO
var _last_rail: GrindRail
var _last_rail_timer := 0.0
var _latch_block := 0.0
var _rail_side := 1.0       # raya hangi yandan gelindi (+1 sağ, -1 sol; gidiş yönüne göre)

const COYOTE_TIME := 0.1
var _windup := -1.0          # >= 0: ollie hazırlığı sürüyor
var _double_used := false
var _jump_base_y := 0.0      # son kalkışın (yerden ayrılma) yüksekliği
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
	stand_up()
	cancel_grind()
	_end_skitch(false)
	fall_time = 0.0
	board_anim = BoardAnim.NONE
	if on_foot:
		on_foot = false
		SkateInput.set_on_foot(false)
		mode_changed.emit(false)
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
	_latch_block = maxf(_latch_block - delta, 0.0)
	if stumble_time > 0.0:
		stumble_time = maxf(stumble_time - delta, 0.0)
		var t := STUMBLE_TIME - stumble_time
		if t > STUMBLE_FOOT_DOWN.x and t < STUMBLE_FOOT_DOWN.y and grounded:
			speed = move_toward(speed, 0.0, stumble_brake * delta)

	if _stow_t >= 0.0:
		_stow_t += delta
		if _stow_t >= STOW_DROP:
			_stow_t = -1.0
			var slot := inventory.find("")
			var it := held_item
			if slot >= 0 and it != "":
				inventory[slot] = it
			held_item = ""
			held_node = null
			inventory_changed.emit()
			item_stowed.emit(it)
	if sitting:
		_sit_t += delta
		velocity = Vector3.ZERO
		speed = 0.0
		inp.consume_skitch()
		# Joystick'i itmek, zıplamak ya da kaykay butonu: kalk
		var stand := _sit_t > 0.6 and (inp.move_vector.length() > 0.5 or _ollie_buffer > 0.0)
		if inp.consume_board_toggle() or stand:
			stand_up()
		_ollie_buffer = 0.0
		return
	if held_in_air:
		velocity = Vector3.ZERO
		speed = 0.0
		inp.consume_board_toggle()
		inp.consume_skitch()
		_ollie_buffer = 0.0
		return
	if fall_time > 0.0 or action_time > 0.0 or input_locked or (bag_open and on_foot):
		inp.consume_board_toggle()
		inp.consume_skitch()
		_ollie_buffer = 0.0
		if action_time > 0.0:
			action_time = maxf(action_time - delta, 0.0)
			if action_time == 0.0:
				action_name = ""
			velocity.x = 0.0
			velocity.z = 0.0
		if input_locked and fall_time <= 0.0 and action_time <= 0.0:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		_fall_move(delta)
		return

	if inp.consume_skitch():
		toggle_skitch()

	if inp.consume_board_toggle():
		if skitch_car:
			_end_skitch(false)
		toggle_board()

	if skitch_car:
		_skitch_move(delta)
		return

	if board_anim != BoardAnim.NONE:
		_ollie_buffer = 0.0
		_board_anim_move(delta)
		return

	if on_foot:
		_foot_move(delta)
		_ollie_buffer = 0.0
		return

	if grinding:
		_grind_move(delta)
		return

	if grounded:
		_ground_move(inp, delta)
	else:
		_air_move(delta)

	_handle_jump_input(delta)
	_auto_hop_check()

	floor_snap_length = 0.0 if _ollie_lock > 0.0 else floor_snap
	var pre_velocity := velocity
	move_and_slide()
	_after_move(pre_velocity)

	if not grounded:
		_try_latch()

	if global_position.y < -1.5:   # denize düştü (ada kıyısı, iskele)
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

	# İtici ivme: eğimde yerçekimi hızlandırır / yavaşlatır
	var drive := g_on_plane.dot(fwd)

	# İtme: ayak, kaykaydan daha hızlı geriye gidiyorsa hızlandırır.
	# Böylece yavaş sürtmek yüksek hızda işe yaramaz, hızlı sürtmek yarar.
	if inp.foot_contact:
		if inp.gesture == SkateInput.Gesture.PUSH:
			# Yokuş aşağı ayak, kaykayla birlikte zaten hızlanan zemine basar: eğim itmenin
			# ulaşabileceği hızı yükseltir (düzdeki en yüksek itme hızıyla aynı kalmasın)
			var downhill := maxf(g_on_plane.dot(fwd), 0.0)
			var foot: float = inp.foot_speed + minf(downhill * downhill_push_gain, downhill_push_max)
			drive += push_grip * clampf((foot - speed) / push_taper, 0.0, 1.0)
		elif inp.gesture == SkateInput.Gesture.REVERSE:
			# Ayak ileri doğru iter, kaykay geri gider. Verim düşük: daha çok efor.
			var rev_foot := minf(inp.foot_speed * reverse_efficiency, reverse_max_speed)
			drive -= push_grip * clampf((rev_foot + speed) / push_taper, 0.0, 1.0)

	var resist := rolling_resistance + air_drag * speed * speed
	if inp.brake > 0.0:
		resist += brake_strength * inp.brake

	# Atalet: ivmeler yumuşakça değişir (itme bitince etkisi bir an sürer, fren yavaşça
	# oturur); hız böylece ivmeli artar ve azalır
	_drive_acc = lerpf(_drive_acc, drive, 1.0 - exp(-drive_response * delta))
	_resist_acc = lerpf(_resist_acc, resist, 1.0 - exp(-resist_response * delta))
	speed += _drive_acc * delta
	speed = move_toward(speed, 0.0, _resist_acc * delta)
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
	# Zemine doğru hafif bastırma: Godot yukarı hareket ederken zemine yapıştırmayı
	# kapatır; bu olmadan rampa çıkarken her kare "havada" olur ve animasyon titrer.
	velocity = fwd * speed - n * ground_stick
	inp.board_speed = speed


func _air_move(delta: float) -> void:
	air_time += delta
	velocity.y -= gravity * delta
	heading = heading.rotated(Vector3.UP, -steer * air_steer_rate * delta)
	ground_normal = ground_normal.slerp(Vector3.UP, 1.0 - exp(-4.0 * delta))
	forward_on_ground = heading


## Zıplama girdisi: yerde -> kısa çökme sonra ollie; kenardan yeni çıktıysa
## (coyote) -> hemen ollie; havada -> bir kez double jump (kickflip).
func _handle_jump_input(delta: float) -> void:
	if _windup >= 0.0:
		_windup -= delta
		if _windup < 0.0:
			if grounded or _coyote > 0.0:
				_do_ollie()
		return
	if _ollie_buffer <= 0.0:
		return
	if grounded:
		_ollie_buffer = 0.0
		_windup = ollie_windup
		ollie_started.emit()
	elif _coyote > 0.0:
		_do_ollie()
	elif not _double_used and air_time > 0.12:
		_ollie_buffer = 0.0
		_double_used = true
		# Toplam zirve = normal ollie zirvesinin double_jump_height katı (kalkış noktasına göre)
		var ollie_peak := ollie_speed * ollie_speed / (2.0 * gravity)
		var remaining := ollie_peak * double_jump_height - (global_position.y - _jump_base_y)
		velocity.y = sqrt(2.0 * gravity * maxf(remaining, 0.08))
		double_jumped.emit()


## Ollie hazırlığı (çökme) sürüyor mu? Görsel bunu bilir.
func is_winding_up() -> bool:
	return _windup >= 0.0


func _do_ollie() -> void:
	_jump_base_y = global_position.y
	_ollie_buffer = 0.0
	_coyote = 0.0
	_ollie_lock = 0.15
	if grounded:
		velocity += ground_normal * ground_stick   # zemine bastırmayı geri al
	velocity += Vector3.UP * ollie_speed
	grounded = false
	air_time = 0.0
	ollied.emit()


func _after_move(pre_velocity: Vector3) -> void:
	var was_grounded := grounded
	grounded = is_on_floor() and _ollie_lock <= 0.0

	if grounded:
		_double_used = false
	if grounded and not was_grounded:
		var n := get_floor_normal()
		var fwd := _project_on_plane(heading, n)
		var impact := maxf(-pre_velocity.dot(n), 0.0)
		speed = pre_velocity.dot(fwd)
		ground_normal = n
		air_time = 0.0
		landed.emit(impact)
	elif was_grounded and not grounded and _ollie_lock <= 0.0:
		_jump_base_y = global_position.y
		# Rampadan uçtu veya kenardan düştü: zemine bastırmayı geri al,
		# kısa süre yine ollie yapılabilir
		velocity += ground_normal * ground_stick
		_coyote = COYOTE_TIME
		air_time = 0.0

	_update_floor_surface()
	_handle_walls()


## Yerdeki gövdenin yüzey türünü oku (titreşim ve kamera hissi bunu kullanır).
func _update_floor_surface() -> void:
	var wall_dot := cos(floor_max_angle)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y >= wall_dot:
			var body := c.get_collider() as Node
			if body:
				floor_surface = body.get_meta("surface", "asfalt")
				# Şehrin boyadığı arazi (bina önleri, ara sokaklar) Arnavut kaldırımı
				if floor_surface == "cim" and Sehir.instance and Sehir.instance.paved_at(global_position.x, global_position.z):
					floor_surface = "arnavut"
			return


## Grind yapılan rayın yüzeyi ("metal" / "beton").
func grind_surface() -> String:
	return _rail.surface if _rail else "metal"


func _handle_walls() -> void:
	var worst := Vector3.ZERO
	var worst_into := 0.0
	var wall_dot := cos(floor_max_angle)
	# Alçak basamağa (kaldırım, kavşak kenarı) değdiyse takılma: üstüne çık, hız kaybetme
	if absf(speed) > 0.1 and is_on_wall():
		var mv := Vector3(heading.x, 0.0, heading.z).normalized() * signf(speed)
		if _step_up(mv):
			return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		# Arabaya çarpma (oyuncu sürerken ya da araba üstüne gelirken): sarsılma değil düşme
		var car := col.get_collider() as Araba
		if car and n.y < wall_dot:
			var nh := Vector3(n.x, 0.0, n.z).normalized()
			var rel := maxf(-velocity.dot(nh), 0.0) + maxf(car.speed * car.fwd.dot(nh), 0.0)
			if rel >= stumble_creature_kmh / 3.6:
				knockdown(nh * (rel * 0.5 + 1.0) + car.fwd * car.speed * 0.6)
				return
		if n.y >= wall_dot or n.y < -0.5:
			continue
		var nh := Vector3(n.x, 0.0, n.z).normalized()
		var into := -heading.dot(nh) * signf(speed if grounded else 1.0)
		if into > worst_into:
			worst_into = into
			worst = nh
	if worst_into <= 0.0:
		return
	var strength := absf(speed) * worst_into
	wall_hit.emit(strength)
	if strength >= stumble_wall_kmh / 3.6 and grounded:
		shake()
	if worst_into > 0.85:
		# Kafa kafaya çarpma: hafif geri sekme
		speed = -speed * 0.15
		velocity = Vector3(velocity.x * -0.15, velocity.y, velocity.z * -0.15)
	else:
		# Sıyırma: duvara paralel yöne dön, biraz hız kaybet
		heading = (heading - worst * heading.dot(worst)).normalized()
		speed *= 1.0 - worst_into * wall_speed_loss


# ---------- Yaya ----------

## Kaykaydan in / kaykaya bin. Animasyonlu: binerken yürürken kaykayı yere bırakır,
## üstüne basıp bir kez iter; inerken kaykaydan atlayıp onu altından çekip eline alır.
func toggle_board() -> void:
	if board_anim != BoardAnim.NONE or held_item != "" or bag_open or sitting:
		return
	if on_foot:
		board_anim = BoardAnim.MOUNTING
	elif grounded and not grinding:
		board_anim = BoardAnim.DISMOUNTING
		SkateInput.set_on_foot(true)   # inerken itme hareketleri kapansın
	else:
		return
	board_anim_time = 0.0


func _board_anim_move(delta: float) -> void:
	board_anim_time += delta
	if board_anim == BoardAnim.MOUNTING:
		speed = MOUNT_SPEED
	else:
		speed = move_toward(speed, 0.0, 9.0 * delta)
	var hv := heading * speed
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - gravity * delta
	forward_on_ground = heading
	ground_normal = Vector3.UP
	floor_snap_length = floor_snap
	move_and_slide()
	grounded = is_on_floor()

	if board_anim == BoardAnim.MOUNTING and board_anim_time >= MOUNT_TIME:
		board_anim = BoardAnim.NONE
		on_foot = false
		speed = MOUNT_SPEED + 1.0        # son karedeki itiş
		SkateInput.set_on_foot(false)
		mode_changed.emit(false)
	elif board_anim == BoardAnim.DISMOUNTING and board_anim_time >= DISMOUNT_TIME:
		board_anim = BoardAnim.NONE
		on_foot = true
		speed = minf(speed, walk_speed)
		mode_changed.emit(true)


func _foot_move(delta: float) -> void:
	var mv: Vector2 = SkateInput.move_vector
	var want := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam and mv.length() > 0.0:
		var f := -cam.global_basis.z
		var r := cam.global_basis.x
		f = Vector3(f.x, 0.0, f.z).normalized()
		r = Vector3(r.x, 0.0, r.z).normalized()
		want = (r * mv.x + f * mv.y).limit_length(1.0)

	# Joystick yarıya kadar: yürüme; sonuna kadar: koşu
	var mag := want.length()
	var target_speed := 0.0
	if mag > 0.0:
		target_speed = walk_speed * minf(mag / 0.7, 1.0)
		if mag > 0.75:
			target_speed = lerpf(walk_speed, run_speed, (mag - 0.75) / 0.25)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var dir := want.normalized() if mag > 0.0 else Vector3.ZERO
	hv = hv.move_toward(dir * target_speed, walk_accel * delta)
	if want.length() > 0.1:
		var ang := heading.signed_angle_to(want.normalized(), Vector3.UP)
		heading = heading.rotated(Vector3.UP, clampf(ang, -walk_turn_rate * delta, walk_turn_rate * delta)).normalized()

	velocity.x = hv.x
	velocity.z = hv.z
	if _ollie_buffer > 0.0 and (is_on_floor() or _coyote > 0.0):
		_ollie_buffer = 0.0
		_coyote = 0.0
		velocity.y = foot_jump_speed
		floor_snap_length = 0.0
		foot_jumped.emit()
	elif is_on_floor() and velocity.y <= 0.0:
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	speed = hv.length()
	forward_on_ground = heading
	ground_normal = Vector3.UP
	if velocity.y <= 0.0:
		floor_snap_length = floor_snap
	var was := grounded
	var want_dir := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if is_on_wall() and want_dir.length() > 0.3:
		_step_up(want_dir.normalized())
	grounded = is_on_floor()
	if was and not grounded and velocity.y <= 0.0:
		_coyote = COYOTE_TIME     # kenardan düştü: kısa süre yine zıplanabilir
	if grounded and not was:
		landed.emit(0.0)
	_update_floor_surface()
	SkateInput.board_speed = 0.0
	if global_position.y < -1.5:   # denize düştü (ada kıyısı, iskele)
		respawn()


# ---------- Grind ----------

func _try_latch() -> void:
	if _latch_block > 0.0:
		return
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
	var side := (rail.direction * _rail_sign).cross(Vector3.UP).normalized()
	var off := Vector3(_snap_offset.x, 0.0, _snap_offset.z).dot(side)
	_rail_side = signf(off) if absf(off) > 0.02 else (1.0 if randf() < 0.5 else -1.0)
	_double_used = false
	_windup = -1.0
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
	elif speed < 0.3 or ((_rail_pos <= 0.0 or _rail_pos >= _rail.length) and not _continue_rail()):
		_exit_grind(false)

	if global_position.y < -1.5:   # denize düştü (ada kıyısı, iskele)
		respawn()


## Ray ucunda, ucu ucuna eklenmiş bir sonraki parça varsa (eğri bariyer, uzun kenar)
## zıplamadan ona geç: grind kesintisiz sürer.
func _continue_rail() -> bool:
	var end := _rail.b if _rail_sign > 0.0 else _rail.a
	var d := _rail.direction * _rail_sign
	var over := _rail_pos - _rail.length if _rail_sign > 0.0 else -_rail_pos
	for node in get_tree().get_nodes_in_group("grind_rails"):
		var r := node as GrindRail
		if r == _rail:
			continue
		var sg := 0.0
		if r.a.distance_squared_to(end) < 0.01:
			sg = 1.0
		elif r.b.distance_squared_to(end) < 0.01:
			sg = -1.0
		if sg == 0.0 or (r.direction * sg).dot(d) < 0.8:
			continue
		_rail = r
		_rail_sign = sg
		_rail_pos = over if sg > 0.0 else r.length - over
		_snap_offset = global_position - r.point_at(clampf(_rail_pos, 0.0, r.length))
		return true
	return false


func _exit_grind(jump: bool) -> void:
	grinding = false
	var d := _rail.direction * _rail_sign
	velocity = d * speed + Vector3.UP * (ollie_speed if jump else grind_exit_pop)
	# Zıplayınca raydan her zaman yana atlar: joystick hangi yöne basılıysa oraya,
	# basılı değilse raya gelinen yana. Kısa süre hiçbir raya tutunmaz.
	var hand: float = SkateInput.steer_target
	var transfer := jump
	if jump:
		var side := d.cross(Vector3.UP).normalized()
		var sg := signf(hand) if absf(hand) > 0.3 else _rail_side
		velocity += side * sg * grind_side_jump
		heading = (heading + side * sg * 0.35).normalized()
		_latch_block = grind_exit_block
		_jump_base_y = global_position.y
		_double_used = false
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


## Bir canlıya (yaya) çarpınca. Yavaşken yalnız biraz hız kaybı; stumble_creature_kmh
## üstünde belirgin yavaşlar ve sarsılır (ayağını yere koyup kendiliğinden geri biner).
func stumble(_away: Vector3) -> void:
	if on_foot or board_anim != BoardAnim.NONE:
		return
	if absf(speed) < stumble_creature_kmh / 3.6:
		speed *= 0.85
		return
	speed *= 0.55
	shake()


## Sarsılma animasyonunu başlat (yayaya / sabit nesneye sert çarpma).
func shake() -> void:
	if stumble_time > 0.0 or on_foot or grinding or board_anim != BoardAnim.NONE:
		return
	stumble_time = STUMBLE_TIME
	stumbled.emit()


# ---------- Kesintisiz sürüş: kendiliğinden zıplama ve basamak çıkma ----------

## İleride (dir yönünde, reach mesafe içinde) aşılabilir alçak bir basamak var mı?
## Varsa ayak seviyesine göre yüksekliği, yoksa -1. Üstünde gövdeyi kesecek engel olmamalı.
func _ledge_ahead(dir: Vector3, reach: float) -> float:
	if dir.length_squared() < 0.01:
		return -1.0
	var space := get_world_3d().direct_space_state
	var p := global_position
	var excl: Array[RID] = [get_rid()]
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.06, p + Vector3.UP * 0.06 + dir * reach, collision_mask, excl))
	if hit.is_empty():
		return -1.0
	var n: Vector3 = hit.normal
	if n.y > 0.6:
		return -1.0                   # rampa / eğim: zaten çıkılır
	var nh := Vector3(n.x, 0.0, n.z).normalized()
	if -nh.dot(dir) < 0.3:
		return -1.0                   # çok yandan sıyırıyor: duvar gibi kayar
	var probe: Vector3 = hit.position + dir * 0.22
	var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (step_max + 0.4), Vector3(probe.x, p.y - 0.05, probe.z), collision_mask, excl))
	if top.is_empty() or top.normal.y < 0.8:
		return -1.0
	var h: float = top.position.y - p.y
	if h <= 0.02 or h > step_max:
		return -1.0
	# Basamağın üstü açık mı (bank, araba, duvar değil)
	var above := p + Vector3.UP * (h + 0.35)
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(above, above + dir * (reach + 0.5), collision_mask, excl)).is_empty():
		return -1.0
	return h


## Sürerken kaldırım yaklaşınca tam zamanında küçük bir zıplama
func _auto_hop_check() -> void:
	if not auto_hop or not grounded or _windup >= 0.0 or _ollie_lock > 0.0 or absf(speed) < 1.6:
		return
	var dir := Vector3(heading.x, 0.0, heading.z).normalized() * signf(speed)
	# Basamağa varmadan yükselmiş olacak kadar önceden (yüksek hızda daha erken)
	var reach := absf(speed) * 0.11 + 0.3
	var h := _ledge_ahead(dir, reach)
	if h < 0.0:
		return
	_jump_base_y = global_position.y
	velocity += ground_normal * ground_stick
	velocity.y = sqrt(2.0 * gravity * (h + auto_hop_clear))
	grounded = false
	_coyote = 0.0
	_ollie_lock = 0.12
	air_time = 0.0
	auto_hopped.emit()


## Değilen alçak basamağın üstüne çık (yavaşken, açılı girerken, yayayken)
func _step_up(dir: Vector3) -> bool:
	var h := _ledge_ahead(dir, 0.55)
	if h < 0.0:
		return false
	global_position += Vector3.UP * (h + 0.015) + dir * 0.06
	velocity.y = maxf(velocity.y, 0.0)
	return true


# ---------- Envanter ----------

## Çanta butonu: yayayken çantayı sırtından alıp açar / kapatıp sırtına takar
func toggle_bag() -> void:
	if fall_time > 0.0 or held_in_air or sitting:
		return
	# Açılırken tekrar basılırsa da kapanır (açma yarıda kesilir)
	if action_time > 0.0 and not (bag_open and action_name == "canta_ac"):
		return
	if bag_open:
		bag_open = false
		if on_foot:
			action_time = 0.0
			play_action("canta_kapat", BAG_ANIM_TIME)
		bag_changed.emit(false)
		return
	if on_foot:
		if held_item != "":
			return                       # eli dolu: önce çantaya at
		play_action("canta_ac", BAG_ANIM_TIME)
	bag_open = true
	bag_changed.emit(true)


## Banka otur: front = oturağın önündeki yer noktası, facing = oturanın baktığı yön,
## seat = oturan kökünün olacağı nokta (kalça oturağın üstüne gelir)
func sit(front: Vector3, facing: Vector3, seat: Vector3) -> bool:
	if sitting or not on_foot or not is_on_floor() or action_time > 0.0 or fall_time > 0.0 or bag_open or input_locked:
		return false
	global_position = Vector3(front.x, global_position.y, front.z)
	reset_physics_interpolation()
	heading = Vector3(facing.x, 0.0, facing.z).normalized()
	forward_on_ground = heading
	sit_offset = seat - global_position
	velocity = Vector3.ZERO
	speed = 0.0
	sitting = true
	_sit_t = 0.0
	sat_down.emit()
	return true


func stand_up() -> void:
	if not sitting:
		return
	sitting = false
	sit_offset = Vector3.ZERO
	stood_up.emit()


## Elindeki eşyayı çantaya at (yer varsa); 14. karede çantada olur
func stow_held() -> bool:
	if held_item == "" or not on_foot or action_time > 0.0 or bag_open or inventory.find("") < 0:
		return false
	play_action("cantaya_koy", STOW_TIME)
	_stow_t = 0.0
	stow_started.emit(held_item)
	return true


## Eşyayı eline al (görsel: düğüm sol ele oturur)
func hold_item(item: String, node: Node3D) -> void:
	held_item = item
	held_node = node
	inventory_changed.emit()


## Eldeki eşyayı bırak (rafa geri koydu): görsel düğümü çağıran yönetir
func release_held() -> void:
	held_item = ""
	held_node = null
	inventory_changed.emit()


## Eldeki ve çantadaki belirli eşyaları geri ver (yakalanınca)
func take_back(items: Array) -> void:
	if held_item in items:
		held_item = ""
		held_node = null
	for i in inventory.size():
		if inventory[i] in items:
			inventory[i] = ""
	inventory_changed.emit()


# ---------- Bağlam eylemleri ----------

## Tek seferlik eylem animasyonu (yayayken): süre boyunca yerinde durur
func play_action(n: String, duration: float) -> void:
	if not on_foot or fall_time > 0.0 or action_time > 0.0:
		return
	action_name = n
	action_time = duration
	speed = 0.0
	velocity = Vector3(0.0, velocity.y, 0.0)
	action_started.emit(n)


## Bağlam butonu basıldı (dokunmatik ya da F tuşu)
func press_context(id: String) -> void:
	context_action.emit(id)


# ---------- Araba: düşme ve tutunma ----------

## Araba çarptı: oyuncu savrulur, düşer, kalkar ve kendiliğinden kaykaya biner.
func knockdown(push: Vector3) -> void:
	if fall_time > 0.0:
		return
	stand_up()
	cancel_grind()
	_end_skitch(false)
	if board_anim == BoardAnim.DISMOUNTING:
		on_foot = true      # inerken çarpıldı: yaya düşer
		mode_changed.emit(true)
	elif board_anim == BoardAnim.MOUNTING:
		on_foot = false
		SkateInput.set_on_foot(false)
		mode_changed.emit(false)
	board_anim = BoardAnim.NONE
	stumble_time = 0.0
	fall_on_foot = on_foot
	fall_time = FOOT_FALL_TIME if on_foot else FALL_TIME
	speed = 0.0
	velocity = Vector3(push.x, 0.0, push.z).limit_length(8.0) + Vector3.UP * 2.2
	grounded = false
	knocked_down.emit()


func _fall_move(delta: float) -> void:
	fall_time = maxf(fall_time - delta, 0.0)
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, (5.0 if is_on_floor() else 1.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = -0.5 if is_on_floor() and velocity.y <= 0.0 else velocity.y - gravity * delta
	speed = 0.0
	forward_on_ground = heading
	ground_normal = Vector3.UP
	floor_snap_length = floor_snap
	move_and_slide()
	grounded = is_on_floor()
	SkateInput.board_speed = 0.0
	if global_position.y < -1.5:
		fall_time = 0.0
		respawn()


## Tutun / bırak (buton ya da Q).
func toggle_skitch() -> void:
	if skitch_car:
		_end_skitch(false)
	elif skitch_candidate and is_instance_valid(skitch_candidate) and not on_foot and grounded 			and board_anim == BoardAnim.NONE and not grinding:
		skitch_car = skitch_candidate
		skitch_changed.emit(true)


func _end_skitch(jump: bool) -> void:
	if not skitch_car:
		return
	if is_instance_valid(skitch_car):
		heading = Vector3(skitch_car.fwd.x, 0.0, skitch_car.fwd.z).normalized()
		speed = minf(skitch_car.speed + 0.4, max_speed)
	skitch_car = null
	skitch_changed.emit(false)
	if jump:
		_ollie_buffer = OLLIE_BUFFER_TIME


## Arabanın arkasında çekiliş: kök tutunma noktasına yay gibi çekilir, hız ve yön arabanın.
func _skitch_move(delta: float) -> void:
	if not is_instance_valid(skitch_car) or not skitch_car.visible:
		_end_skitch(false)
		return
	if _ollie_buffer > 0.0:
		_ollie_buffer = 0.0
		_end_skitch(true)
		return
	var target: Vector3 = skitch_car.skitch_anchor()
	var to := target - global_position
	if Vector2(to.x, to.z).length() > 2.6:
		_end_skitch(false)   # araba çok sert döndü / bir şeye takıldık
		return
	var f: Vector3 = skitch_car.fwd
	heading = Vector3(f.x, 0.0, f.z).normalized()
	speed = skitch_car.speed
	var n := get_floor_normal() if is_on_floor() else Vector3.UP
	ground_normal = n
	forward_on_ground = _project_on_plane(heading, n)
	var pull := Vector3(to.x, 0.0, to.z) * 8.0
	velocity = forward_on_ground * speed + pull - n * ground_stick
	floor_snap_length = floor_snap
	move_and_slide()
	grounded = is_on_floor()
	_update_floor_surface()
	SkateInput.board_speed = speed


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
