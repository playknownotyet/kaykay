extends Camera3D
## Kaykay sürüşü için arkadan takip eden kamera.
##
## Hız hissi üç katmandan gelir:
##  1. Kamera yavaşken karaktere çok yakın, hızlandıkça geri çekilir.
##  2. Görüş açısı (FOV) hızla genişler: kenardaki nesneler hızla akar.
##  3. Ekran efekti (speed_fx.gd): kenarlarda bükülme + radyal bulanıklık.
## Ek olarak yüksek hızda tekerlek titreşimi gibi ince bir sarsıntı var.
## (Dükkan içi / stealth kamerası ileride ayrı bir mod olarak eklenecek.)

@export var target: SkateController
@export var distance_slow := 2.3
@export var distance_fast := 4.2
@export var height_slow := 1.3
@export var height_fast := 1.6
@export var look_height := 0.85
@export var look_ahead := 2.5
@export var fov_slow := 60.0
@export var fov_fast := 88.0
## Bu hızda (m/sn) tüm hız etkileri tam güce ulaşır.
@export var fast_speed := 10.0
@export var follow_sharpness := 9.0
@export var turn_sharpness := 4.0
## Yüksek hızda yol titreşimi (metre).
@export var vibration := 0.012

## 0..1, hız etkilerinin ortak çarpanı (ekran efekti de bunu okur).
var speed01 := 0.0

var _yaw := 0.0
var _look := Vector3.ZERO
var _shake := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	# Kamerayı _process içinde kendimiz yumuşattığımız için fizik
	# interpolasyonunu kapatıyoruz; hedefin interpolasyonlu konumunu okuyoruz.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_noise.frequency = 2.5
	if target:
		target.landed.connect(func(impact: float): _shake = clampf(impact * 0.012, 0.0, 0.08))
		snap()


func snap() -> void:
	var pos := target.global_position
	_yaw = _heading_yaw()
	speed01 = 0.0
	global_position = pos - _yaw_dir() * distance_slow + Vector3.UP * height_slow
	_look = pos + Vector3.UP * look_height
	look_at(_look)


func _process(delta: float) -> void:
	if not target:
		return
	_time += delta
	var pos := target.get_global_transform_interpolated().origin

	# Hız çarpanı yumuşak artar/azalır; ease ile düşük hızda az, yüksekte çok etki
	var raw := clampf(absf(target.speed) / fast_speed, 0.0, 1.0) if target.speed > 0.0 else 0.0
	speed01 = lerpf(speed01, raw, 1.0 - exp(-2.5 * delta))
	var s := ease(speed01, 1.6)

	_yaw = lerp_angle(_yaw, _heading_yaw(), 1.0 - exp(-turn_sharpness * delta))
	var dir := _yaw_dir()

	var dist := lerpf(distance_slow, distance_fast, s)
	var h := lerpf(height_slow, height_fast, s)
	var desired := pos - dir * dist + Vector3.UP * h
	var t := 1.0 - exp(-follow_sharpness * delta)
	var cam := global_position
	cam.x = lerpf(cam.x, desired.x, t)
	cam.z = lerpf(cam.z, desired.z, t)
	cam.y = lerpf(cam.y, desired.y, 1.0 - exp(-5.0 * delta))
	cam.y = maxf(cam.y, pos.y + 0.5)
	global_position = cam

	var look_target := pos + Vector3.UP * look_height + dir * look_ahead * s
	_look = _look.lerp(look_target, 1.0 - exp(-12.0 * delta))

	_shake = lerpf(_shake, 0.0, 1.0 - exp(-10.0 * delta))
	var vib := vibration * s * float(target.grounded)
	var amp := _shake + vib
	var jitter := Vector3(
		_noise.get_noise_2d(_time * 40.0, 0.0),
		_noise.get_noise_2d(0.0, _time * 40.0),
		0.0) * amp
	look_at(_look + jitter)

	fov = lerpf(fov_slow, fov_fast, s)


func _heading_yaw() -> float:
	return atan2(-target.heading.x, -target.heading.z)


func _yaw_dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))
