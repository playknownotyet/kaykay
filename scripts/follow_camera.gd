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

## 0..1, hız etkilerinin ortak çarpanı (ekran efekti de bunu okur).
var speed01 := 0.0

var _yaw := 0.0
var _look := Vector3.ZERO
var _shake := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0
var _bump := 0.0        # dikey sekme (m)
var _bump_vel := 0.0
var _base_pos := Vector3.ZERO   # sekmesiz, yumuşatılmış kamera konumu


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
	var pos := target.get_global_transform_interpolated().origin

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

	var dist := lerpf(distance_slow, distance_fast, s)
	var h := lerpf(height_slow, height_fast, s)
	var desired := pos - dir * dist + Vector3.UP * h
	var t := 1.0 - exp(-follow_sharpness * delta)
	var cam := _base_pos
	cam.x = lerpf(cam.x, desired.x, t)
	cam.z = lerpf(cam.z, desired.z, t)
	cam.y = lerpf(cam.y, desired.y, 1.0 - exp(-5.0 * delta))
	cam.y = maxf(cam.y, pos.y + 0.5)
	_base_pos = cam
	global_position = cam

	var look_target := pos + Vector3.UP * look_height + dir * look_ahead * s
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


func _heading_yaw() -> float:
	return atan2(-target.heading.x, -target.heading.z)


func _yaw_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))
