extends Camera3D
## Kaykay sürüşü için arkadan takip eden kamera.
##
## Hız hissi üç katmandan gelir:
##  1. Kamera yavaşken karaktere çok yakın, hızlandıkça geri çekilir.
##  2. Görüş açısı (FOV) hızla genişler: kenardaki nesneler hızla akar.
##  3. Ekran efekti (speed_fx.gd): kenarlarda bükülme + radyal bulanıklık.
## Ek olarak zemin hissi: yüzeye göre çok hafif titreme ve taş/iniş sekmeleri
## (surface_feedback.gd). Abartısız, sadece hissiyat.
## (Dükkan içi / stealth kamerası ileride ayrı bir mod olarak eklenecek.)

@export var target: SkateController
@export var distance_slow := 2.2
@export var distance_fast := 3.0
@export var height_slow := 1.3
@export var height_fast := 1.6
@export var look_height := 0.85
@export var look_ahead := 2.5
@export var fov_slow := 60.0
@export var fov_fast := 87.0
## Bu hızda (m/sn) tüm hız etkileri tam güce ulaşır.
@export var fast_speed := 9.5
@export var follow_sharpness := 8.5
@export var turn_sharpness := 4.0
@export var feedback: SurfaceFeedback
## Taş / iniş sekmesinin yay sertliği ve sönümü
@export var bump_stiffness := 260.0
@export var bump_damping := 22.0

## Bakış joystick'i (kaykaydayken): tam yana çekince kamera bu kadar döner (derece); bırakınca geri gelir
@export var peek_max := 110.0
## Tam yukarı / aşağı çekince bakış noktası bu kadar yükselir / alçalır (m)
@export var peek_up := 2.6
@export var peek_down := 1.4

@export_group("Yaya kamerası")
## Ekranda parmakla çevirme: bir ekran yüksekliği kaydırınca dönüş (derece)
@export var foot_drag_yaw := 210.0
@export var foot_drag_pitch := 120.0
## Kamera joystick'i tam saptırınca dönüş hızı (derece / sn)
@export var foot_yaw_speed := 170.0
@export var foot_pitch_speed := 95.0
@export var foot_distance := 3.4
@export var foot_look_height := 1.05
## Varsayılan bakış açısı (yukarıdan, derece) ve sınırlar
@export var foot_pitch_default := 16.0
@export var foot_pitch_min := -12.0
@export var foot_pitch_max := 62.0
## Joystick bırakıldıktan bu kadar sonra (sn) kamera yürüyüş yönünün arkasına döner
@export var foot_assist_delay := 1.1
@export var foot_assist_rate := 1.6

## 0..1, hız etkilerinin ortak çarpanı (ekran efekti de bunu okur).
var speed01 := 0.0

var _yaw := 0.0
var _look := Vector3.ZERO
var _shake := 0.0


## Dışarıdan kısa sarsıntı (ör. yerden rampa çıkınca)
func add_shake(a: float) -> void:
	_shake = maxf(_shake, a)
var _noise := FastNoiseLite.new()
var _time := 0.0
var _bump := 0.0        # dikey sekme (m)
var _bump_vel := 0.0
var _base_pos := Vector3.ZERO   # sekmesiz, yumuşatılmış kamera konumu
var _pitch := 0.28              # yaya kamerası bakış açısı (radyan)
var _yaw_vel := 0.0
var _pitch_vel := 0.0
var _idle_cam := 10.0           # kamera joystick'i ne zamandır boşta
var _foot_dist := 3.4           # engel yüzünden kısalabilen mesafe
var _foot_base := 3.4           # engelsiz mesafe (geçişte yumuşakça foot_distance'a gider)
var _foot_look := 1.05          # bakış yüksekliği (geçişte yumuşak)
var _in_foot := false
var _peek := Vector2.ZERO       # bakış joystick'i (yumuşatılmış; x yan, y yukarı)


func _ready() -> void:
	# Kamerayı _process içinde kendimiz yumuşattığımız için fizik
	# interpolasyonunu kapatıyoruz; hedefin interpolasyonlu konumunu okuyoruz.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	# Yakın düzlemi biraz uzak: düşük çözünürlükte derinlik hassasiyeti artar,
	# üst üste binen yüzeyler (tişört/pantolon vb.) titreşmez.
	near = 0.12
	far = 400.0
	_noise.frequency = 2.5
	if target:
		target.landed.connect(func(impact: float): _shake = clampf(impact * 0.012, 0.0, 0.08))
		snap()
	if feedback:
		feedback.bump.connect(func(strength: float): _bump_vel -= strength * 40.0)


func snap() -> void:
	var pos := target.global_position
	_yaw = _heading_yaw()
	speed01 = 0.0
	global_position = pos - _yaw_dir() * distance_slow + Vector3.UP * height_slow
	_base_pos = global_position
	_look = pos + Vector3.UP * look_height
	look_at(_look)


func _process(delta: float) -> void:
	if not target:
		return
	_time += delta
	var drag := SkateInput.consume_cam_drag()
	var pos := target.get_global_transform_interpolated().origin
	if target.on_foot and target.board_anim == SkateController.BoardAnim.NONE:
		if not _in_foot:
			_enter_foot(pos)
		_peek = Vector2.ZERO
		_foot_camera(delta, pos, drag)
		return
	_in_foot = false
	# Bakış joystick'i (ya da klavyede I J K L): her yöne kısa bakış, bırakınca öne döner
	var peek_in: Vector2 = SkateInput.peek if SkateInput.peek.length() > 0.01 else SkateInput.cam_stick
	var peek_rate := 9.0 if peek_in.length() > _peek.length() else 5.5
	_peek = _peek.lerp(peek_in, 1.0 - exp(-peek_rate * delta))

	# Hız çarpanı yumuşak artar/azalır; ease ile düşük hızda az, yüksekte çok etki
	var raw := clampf(absf(target.speed) / fast_speed, 0.0, 1.0) if target.speed > 0.0 and not target.on_foot else 0.0
	speed01 = lerpf(speed01, raw, 1.0 - exp(-2.5 * delta))
	var s := ease(speed01, 1.6)

	var turn := turn_sharpness
	if target.on_foot:
		# Yürürken kamera yalnızca karakter kameradan uzaklaşırken arkasına geçer;
		# kameraya doğru yürüyünce etrafında dönmez (yön kameraya göre olduğu için).
		var away := maxf(_yaw_dir().dot(target.heading), 0.0)
		turn = 1.5 * away * clampf(target.speed / 1.0, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, _heading_yaw(), 1.0 - exp(-turn * delta))
	var dir := _yaw_dir()
	if absf(_peek.x) > 0.001:
		var a := _yaw - _peek.x * deg_to_rad(peek_max)
		dir = Vector3(-sin(a), 0.0, -cos(a))

	var dist := lerpf(distance_slow, distance_fast, s)
	var h := lerpf(height_slow, height_fast, s)
	# Yukarı bakış: kamera alçalır, bakış noktası yükselir; aşağı bakış: kamera yükselir
	var py := _peek.y
	if py > 0.0:
		h = lerpf(h, 0.55, py * 0.8)
	else:
		h += -py * 1.6
	var desired := pos - dir * dist + Vector3.UP * h
	var t := 1.0 - exp(-follow_sharpness * delta)
	var cam := _base_pos
	cam.x = lerpf(cam.x, desired.x, t)
	cam.z = lerpf(cam.z, desired.z, t)
	cam.y = lerpf(cam.y, desired.y, 1.0 - exp(-5.0 * delta))
	cam.y = maxf(cam.y, pos.y + 0.5)
	_base_pos = cam
	global_position = cam

	var look_target := pos + Vector3.UP * (look_height + maxf(py, 0.0) * peek_up - maxf(-py, 0.0) * peek_down) + dir * look_ahead * s
	_look = _look.lerp(look_target, 1.0 - exp(-12.0 * delta))

	# Zemin hissi: yüzeye göre sürekli titreme + taş/iniş sekmesi (yaylı, kısa)
	_shake = lerpf(_shake, 0.0, 1.0 - exp(-10.0 * delta))
	var rumble := feedback.camera_rumble if feedback else 0.0
	var amp := _shake + rumble
	var jitter := Vector3(
		_noise.get_noise_2d(_time * 40.0, 0.0),
		_noise.get_noise_2d(0.0, _time * 40.0),
		0.0) * amp
	_bump_vel += (-_bump * bump_stiffness - _bump_vel * bump_damping) * delta
	_bump += _bump_vel * delta
	_bump = clampf(_bump, -0.03, 0.03)
	global_position = _base_pos + Vector3.UP * _bump
	look_at(_look + jitter)

	fov = lerpf(fov_slow, fov_fast, s)


## Kaykaydan inince kamera olduğu yerden devam eder (açı ve mesafe sonra yumuşakça yaya ayarına geçer)
func _enter_foot(pos: Vector3) -> void:
	_in_foot = true
	_foot_look = look_height
	var off := global_position - (pos + Vector3.UP * _foot_look)
	var L := maxf(off.length(), 0.5)
	_foot_dist = L
	_foot_base = L
	_pitch = asin(clampf(off.y / L, -0.99, 0.99))
	_yaw = atan2(off.x, off.z)
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	_idle_cam = 0.0


## Yaya: üçüncü şahıs yörünge kamerası. Joystick dönüş hızı verir (yumuşak ivmeyle), boşta
## kalınca ve karakter yürürken kamera yavaşça arkasına geçer, bakış açısı varsayılana döner.
## Arada duvar / ağaç varsa kamera öne çekilir.
func _foot_camera(delta: float, pos: Vector3, drag := Vector2.ZERO) -> void:
	# Ekranda parmak kaydırma: sağa çekince sağa, yukarı çekince yukarı bakar
	if drag != Vector2.ZERO:
		_yaw -= drag.x * deg_to_rad(foot_drag_yaw)
		_pitch = clampf(_pitch + drag.y * deg_to_rad(foot_drag_pitch), deg_to_rad(foot_pitch_min), deg_to_rad(foot_pitch_max))
		_yaw_vel = 0.0
		_pitch_vel = 0.0
		_idle_cam = 0.0
	var stick: Vector2 = SkateInput.cam_stick
	var want_yaw := -stick.x * deg_to_rad(foot_yaw_speed)
	var want_pitch := -stick.y * deg_to_rad(foot_pitch_speed)
	_yaw_vel = lerpf(_yaw_vel, want_yaw, 1.0 - exp(-14.0 * delta))
	_pitch_vel = lerpf(_pitch_vel, want_pitch, 1.0 - exp(-14.0 * delta))
	_yaw += _yaw_vel * delta
	_pitch = clampf(_pitch + _pitch_vel * delta, deg_to_rad(foot_pitch_min), deg_to_rad(foot_pitch_max))
	if stick.length() > 0.05 or drag != Vector2.ZERO:
		_idle_cam = 0.0
	else:
		_idle_cam += delta
	# Geçişten sonra mesafe, bakış yüksekliği ve açı yaya ayarına süzülür
	_foot_base = lerpf(_foot_base, foot_distance, 1.0 - exp(-1.5 * delta))
	_foot_look = lerpf(_foot_look, foot_look_height, 1.0 - exp(-2.0 * delta))
	if _idle_cam > foot_assist_delay:
		_pitch = lerp_angle(_pitch, deg_to_rad(foot_pitch_default), 1.0 - exp(-0.6 * delta))
		var moving := clampf(target.speed / 1.5, 0.0, 1.0)
		# Kameraya doğru yürürken arkaya dönmez (yön kameraya göre; dönerse hareket karışır)
		var away := clampf(_yaw_dir().dot(target.heading) + 0.3, 0.0, 1.0)
		_yaw = lerp_angle(_yaw, _heading_yaw(), 1.0 - exp(-foot_assist_rate * moving * away * delta))
		_pitch = lerp_angle(_pitch, deg_to_rad(foot_pitch_default), 1.0 - exp(-0.8 * moving * delta))

	var look := pos + Vector3.UP * _foot_look
	var back := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	# Engel: bakış noktasından kameraya ışın; çarparsa önüne
	var dist := _foot_base
	var q := PhysicsRayQueryParameters3D.create(look, look + back * (_foot_base + 0.3), 0xFFFFFFFF, [target.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(look.distance_to(hit.position) - 0.3, 0.6)
	# İçeri hızlı, dışarı yavaş (duvar kenarında titremesin)
	_foot_dist = lerpf(_foot_dist, dist, 1.0 - exp(-(25.0 if dist < _foot_dist else 3.0) * delta))
	var cam := look + back * _foot_dist
	_base_pos = cam
	global_position = cam
	_look = look
	look_at(look)
	speed01 = lerpf(speed01, 0.0, 1.0 - exp(-2.5 * delta))
	fov = lerpf(fov, fov_slow, 1.0 - exp(-4.0 * delta))


func _heading_yaw() -> float:
	return atan2(-target.heading.x, -target.heading.z)


func _yaw_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))
